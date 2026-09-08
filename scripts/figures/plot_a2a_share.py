#!/usr/bin/env python3
"""Fig 1 (motivation): per-model MoE-layer phase breakdown of the training iteration on the
incumbent 8-GPU island (HGX-8, packet-level, quoted row), as a 100% stacked bar:
Attention | Gate | expert A2A | Experts | Add&Norm.

  A2A      = expert_a2a_ms of the critical-path walk (decomp_critpath.csv) at the quoted
             cliff_all.csv row (system hgx8_pkt, mb 8) -- measured, per EP/model.
  compute  = compute_ms of the same walk, split by op type in proportion to the FlexFlow task
             graph's per-op time along its longest compute path (taskgraph/<graph>.txt):
             MultiHeadAttention -> Attention; Softmax/Group_by/TopK -> Gate; Dense/Aggregate ->
             Experts; LayerNorm/Add/Input/Repartition -> Add&Norm.
Models whose graph .txt is not present are skipped with a warning.

Env: PAPER_RES (default experiments/results/paper), TG (default ../taskgraph), OUT (default .),
     FABRIC (default hgx8_pkt).
"""
import csv, os, re, sys
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
try:
    sys.path.insert(0, os.path.dirname(__file__)); import paper_style as _ps; _ps.apply()
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.environ.get("PAPER_RES", os.path.join(HERE, "..", "..", "experiments", "results", "paper"))
TG = os.environ.get("TG", os.path.join(HERE, "..", "..", "..", "taskgraph"))
OUT = os.environ.get("OUT", ".")
FABRIC = os.environ.get("FABRIC", "hgx8_pkt")
MODELS = [  # label, EP, graph basename
    ("LLaMA-MoE", 16, "llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.txt"),
    ("LLaMA-MoE", 32, "llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.txt"),
    ("Qwen-MoE", 64, "qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.txt"),
    ("Arctic", 128, "arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.txt"),
]
PHASE_OF = {"MultiHeadAttention": "Attention", "Softmax": "Gate", "Group_by": "Gate", "TopK": "Gate",
            "Dense": "Experts", "Aggregate": "Experts", "LayerNorm": "Add&Norm", "Add": "Add&Norm",
            "Input": "Add&Norm", "Repartition": "Add&Norm"}
PHASES = ["Attention", "Gate", "All-to-All", "Experts", "Add&Norm"]
COL = {"Attention": "#8a97a3", "Gate": "#c9d1d8", "All-to-All": "#2b6f7f", "Experts": "#d99a4e", "Add&Norm": "#efd3b0"}

def cp_phases(path):
    sys.setrecursionlimit(200000)
    nodes, adj = {}, defaultdict(list)
    for line in open(path):
        m = re.match(r'\s*node(\d+)\s*\[label="\{\s*([A-Za-z_]+)', line)
        if m:
            nums = re.findall(r'([0-9]\.[0-9]+e[+\-][0-9]+)', line)
            w = (float(nums[0]) + float(nums[1])) if len(nums) >= 2 else 0.0
            nodes[int(m.group(1))] = (m.group(2).rstrip('_'), w); continue
        e = re.match(r'\s*node(\d+)\s*->\s*node(\d+)', line)
        if e: adj[int(e.group(1))].append(int(e.group(2)))
    memo, nxt = {}, {}
    def lp(u):
        if u in memo: return memo[u]
        w = nodes.get(u, ('', 0))[1]; best, bv = w, None
        for v in adj[u]:
            c = w + lp(v)
            if c > best: best, bv = c, v
        memo[u], nxt[u] = best, bv; return best
    s = max(nodes, key=lp); ph = defaultdict(float); u = s
    while u is not None:
        op, w = nodes[u]; ph[PHASE_OF.get(op, "Add&Norm")] += w; u = nxt.get(u)
    return dict(ph)

quoted = {}
for r in csv.DictReader(open(os.path.join(RES, "cliff_all.csv"))):
    if r["system"] == FABRIC and (r.get("quotable") or "").lower() == "yes" and r.get("link_rate_fixed") == "yes" \
            and int(float(r["mb"] or 8)) == 8:
        quoted[int(float(r["ep"]))] = float(r["makespan_ms"])
dec = list(csv.DictReader(open(os.path.join(RES, "decomp_critpath.csv"))))

rows = []
for label, ep, g in MODELS:
    p = os.path.join(TG, g)
    mk = quoted.get(ep)
    c = [x for x in dec if x["label"].startswith(f"{FABRIC} EP={ep}") and mk is not None and abs(float(x["makespan_ms"]) - mk) < 0.05]
    if not os.path.exists(p) or not c:
        print(f"  WARNING {label} EP={ep}: {'graph missing' if not os.path.exists(p) else 'no quoted decomp row'} -- skipped"); continue
    ph = cp_phases(p); tot = sum(ph.values())
    comp, a2a = float(c[0]["compute_ms"]), float(c[0]["expert_a2a_ms"])
    vals = {k: comp * ph.get(k, 0) / tot for k in ("Attention", "Gate", "Experts", "Add&Norm")}
    vals["All-to-All"] = a2a
    it = comp + a2a
    rows.append((f"{label}\nEP={ep}", {k: 100 * v / it for k, v in vals.items()}, it))
    print("  %-10s EP=%3d  iter %.1f ms  A2A %.1f%%  compute split %s" % (label, ep, it, 100 * a2a / it,
          {k: round(100 * v / it, 1) for k, v in vals.items() if k != "All-to-All"}))

if not rows: sys.exit("no rows")
fig, ax = plt.subplots(figsize=(3.45, 0.55 + 0.42 * len(rows)), dpi=200)
ys = list(range(len(rows)))[::-1]
for y, (lab, v, it) in zip(ys, rows):
    left = 0
    for ph in PHASES:
        w = v.get(ph, 0)
        ax.barh(y, w, left=left, height=0.62, color=COL[ph], edgecolor="white", lw=0.4, label=ph if y == ys[0] else None)
        if ph == "All-to-All":
            ax.text(left + w / 2, y, "A2A %.0f%%" % w, ha="center", va="center", fontsize=6.4, color="white", fontweight="bold")
        left += w
ax.set_yticks(ys); ax.set_yticklabels([r[0] for r in rows], fontsize=6.5)
ax.set_xlim(0, 100); ax.set_xlabel("share of training iteration (%)", fontsize=7)
ax.tick_params(axis="x", labelsize=6.5)
ax.legend(ncol=5, frameon=False, fontsize=5.6, loc="lower center", bbox_to_anchor=(0.5, 1.0), handlelength=1.0, columnspacing=0.8, handletextpad=0.4)
for s in ("top", "right"): ax.spines[s].set_visible(False)
fig.tight_layout(pad=0.3)
for ext in ("png", "pdf"):
    fig.savefig(os.path.join(OUT, f"fig_phases.{ext}"))
print("wrote fig_phases.png")
