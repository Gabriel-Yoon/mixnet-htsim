#!/usr/bin/env python3
"""MoE-layer 6-phase breakdown for the MixNet-3 paper-config a2a-dominant proxies (seq1024 L4).
Phases (canonical MoE-layer timeline): Attention | Gate | 1st A2A | Experts | 2nd A2A | Add&Norm.

Compute phases = MEASURED critical-path time (per op, walked along the longest weighted path):
  Attention = MultiHeadAttention (FlexFlow fuses QKV+softmax+O, so the separate Softmax op is the
              MoE GATE softmax, mapped to Gate);  Gate = Softmax + Group_by + TopK ;
  Experts   = Dense + Aggregate ;  Add&Norm = LayerNorm + Add.
A2A comm = htsim glass-optical exposed communication (makespan - compute_cp), split 50/50 into
  dispatch (1st) and combine (2nd) -- symmetric volume.
NOTE: proxies use NO_FULLMEASURE -> Group_by/Aggregate/TopK are skipped (=0); routing compute is
  negligible anyway. mixtral8x7B is TP4 (partly all-reduce); llama/qwen are TP1 (clean a2a)."""
import re, csv, os
from collections import defaultdict, OrderedDict
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
TG = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/mixnet-sim/taskgraph"
MODELS = OrderedDict([  # label -> (txt glob prefix, glass makespan ms from a2a CSV)
    ("Mixtral-8x7B", "mixtral8x7B_paper_dp2tp4pp4_ep8top2_L4_seq1024"),
    ("LLaMA-MoE",    "llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024"),
    ("Qwen-MoE",     "qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024"),
])
PHASE_OF = {"MultiHeadAttention":"Attention", "Softmax":"Gate","Group_by":"Gate","TopK":"Gate",
            "Dense":"Experts","Aggregate":"Experts", "LayerNorm":"Add&Norm","Add":"Add&Norm",
            "Input":"Add&Norm","Repartition":"Add&Norm"}

def cp_phases(path):
    nodes, adj = {}, defaultdict(list)
    for line in open(path):
        m = re.match(r'\s*node(\d+)\s*\[label="\{\s*([A-Za-z_]+)', line)
        if m:
            nums = re.findall(r'([0-9]\.[0-9]+e[+\-][0-9]+)', line)
            w = (float(nums[0])+float(nums[1])) if len(nums)>=2 else 0.0
            nodes[int(m.group(1))] = (m.group(2).rstrip('_'), w); continue
        e = re.match(r'\s*node(\d+)\s*->\s*node(\d+)', line)
        if e: adj[int(e.group(1))].append(int(e.group(2)))
    memo, nxt = {}, {}
    def lp(u):
        if u in memo: return memo[u]
        w=nodes.get(u,('',0))[1]; best,bv=w,None
        for v in adj[u]:
            c=w+lp(v)
            if c>best: best,bv=c,v
        memo[u],nxt[u]=best,bv; return best
    s=max(nodes,key=lp); cp=memo[s]; ph=defaultdict(float); u=s
    while u is not None:
        op,w=nodes[u]; ph[PHASE_OF.get(op,"Add&Norm")]+=w; u=nxt.get(u)
    return cp, ph

# glass makespan per model
glass = {}
with open(f"{FP}/paper_a2a_topo_compare.csv") as f:
    for r in csv.DictReader(f):
        if r["topology"]=="glass_optical": glass[r["model"]]=float(r["makespan_ms"])
# qwen makespan from the side run (if present)
qg = None
if os.path.exists("/tmp/qwen_glass_ms.txt"):
    t=open("/tmp/qwen_glass_ms.txt").read().strip()
    m=re.search(r'(\d+)', t);  qg=float(m.group(1))/1e9 if m else None
MK={"mixtral8x7B":glass.get("mixtral8x7B"),"llamaMoE":glass.get("llamaMoE"),"qwenMoE":qg}

PHASES=["Attention","Gate","1st A2A","Experts","2nd A2A","Add&Norm"]
COL={"Attention":"#41b6c4","Gate":"#fe9929","1st A2A":"#d7301f","Experts":"#225ea8",
     "2nd A2A":"#fc8d59","Add&Norm":"#969696"}
keymap={"Mixtral-8x7B":"mixtral8x7B","LLaMA-MoE":"llamaMoE","Qwen-MoE":"qwenMoE"}

fig, ax = plt.subplots(figsize=(9,5.5))
labels=[]; data={p:[] for p in PHASES}
for lab,glob in MODELS.items():
    import glob as G
    fs=G.glob(f"{TG}/{glob}_*.txt")
    if not fs: continue
    cp,ph=cp_phases(fs[0]); mk=MK.get(keymap[lab])
    comm=max(0.,(mk-cp)) if mk else 0.
    vals={"Attention":ph.get("Attention",0),"Gate":ph.get("Gate",0),"1st A2A":comm/2,
          "Experts":ph.get("Experts",0),"2nd A2A":comm/2,"Add&Norm":ph.get("Add&Norm",0)}
    labels.append(f"{lab}\n(TP{ '4' if 'tp4' in glob else '1'})")
    for p in PHASES: data[p].append(vals[p])
x=np.arange(len(labels)); bottom=np.zeros(len(labels))
for p in PHASES:
    ax.bar(x,data[p],0.55,bottom=bottom,label=p,color=COL[p]); bottom+=np.array(data[p])
for xi in x: ax.text(xi,bottom[xi]+2,f"{bottom[xi]:.0f}",ha="center",fontsize=9)
ax.set_xticks(x); ax.set_xticklabels(labels)
ax.set_ylabel("per-layer time (ms)")
ax.set_title("MoE-layer 6-phase breakdown (paper-config, glass-FB optical, seq1024 L4 proxy)\n"
             "compute = measured critical path; A2A = htsim exposed communication")
ax.legend(fontsize=8,loc="upper left"); ax.grid(axis="y",ls=":",alpha=.5)
fig.tight_layout(); fig.savefig(f"{FP}/moe_6phase_breakdown.png",dpi=150)
print("wrote moe_6phase_breakdown.png")
for lab,glob in MODELS.items():
    import glob as G
    fs=G.glob(f"{TG}/{glob}_*.txt")
    if not fs: continue
    cp,ph=cp_phases(fs[0]); mk=MK.get(keymap[lab])
    print(f"  {lab}: cp={cp:.1f} glass={mk} -> a2a={max(0.,(mk-cp)) if mk else '?'}  "
          f"(Attn {ph.get('Attention',0):.0f}|Gate {ph.get('Gate',0):.0f}|Exp {ph.get('Experts',0):.0f}|AddNorm {ph.get('Add&Norm',0):.0f})")
