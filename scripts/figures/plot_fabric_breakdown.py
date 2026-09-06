#!/usr/bin/env python3
"""mixnet-style per-microbatch breakdown plots for the glass-FB fabric study.

Reads (all under outputs/fabric_plots/, so it runs inside servingsim_docker where the repo
is mounted at /app/LLMServingSim):
  - mixtral8x22B_..._mb<MB>_..._H200.txt   FlexFlow dot dump -> compute critical path
  - mixtral_fabric_sweep.csv               htsim makespan per fabric (glass/nvl72)
  - mixtral_inter_bw_sweep.csv             inter-panel optical BW sweep (optional)

Writes:
  - mixtral_fabric_breakdown.png     per-mb [compute | exposed-comm] per fabric (headline)
  - mixtral_compute_composition.png  per-mb critical-path compute split (attn/FFN/softmax/router)
  - mixtral_inter_bw_sweep.png       makespan vs inter-panel BW (if the CSV exists)

Per-layer numbers; multiply by num_layers (mixtral8x22B = 56) for a full step.
"""
import re, csv, os
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = os.environ.get("FP", "/app/LLMServingSim/outputs/fabric_plots")
MBS = [8, 16, 32, 64]
TXT = lambda mb: f"{FP}/mixtral8x22B_fullmeasure_dp2tp8pp1ep8_mb{mb}_1L_seq1024_H200.txt"

CAT = {"MultiHeadAttention": "attention", "Dense": "FFN/proj (Dense)",
       "Softmax": "softmax", "Aggregate": "MoE router", "Group_by": "MoE router",
       "TopK": "MoE router", "Add": "other", "LayerNorm": "other"}

def parse_dot(path):
    nodes, adj = {}, defaultdict(list)
    for line in open(path):
        m = re.match(r'\s*node(\d+)\s*\[label="\{\s*([A-Za-z_]+)', line)
        if m:
            nid, op = int(m.group(1)), m.group(2).rstrip('_')
            nums = re.findall(r'([0-9]\.[0-9]+e[+\-][0-9]+)', line)
            w = (float(nums[0]) + float(nums[1])) if len(nums) >= 2 else 0.0
            nodes[nid] = (op, w); continue
        e = re.match(r'\s*node(\d+)\s*->\s*node(\d+)', line)
        if e:
            adj[int(e.group(1))].append(int(e.group(2)))
    memo, nxt = {}, {}
    def longest(u):
        if u in memo: return memo[u]
        w = nodes.get(u, ('', 0.0))[1]; best, bv = w, None
        for v in adj[u]:
            c = w + longest(v)
            if c > best: best, bv = c, v
        memo[u], nxt[u] = best, bv; return best
    start = max(nodes, key=longest); cp = memo[start]
    comp = defaultdict(float); u = start
    while u is not None:
        op, w = nodes[u]; comp[CAT.get(op, "other")] += w; u = nxt.get(u)
    return cp, comp

cp, comp = {}, {}
for mb in MBS:
    cp[mb], comp[mb] = parse_dot(TXT(mb))

mk = defaultdict(dict)
with open(f"{FP}/mixtral_fabric_sweep.csv") as f:
    for r in csv.DictReader(f):
        mk[r["fabric"]][int(r["mb"])] = float(r["makespan_ms"])

FABRICS = [("glass", "Glass-FB (512/512, panel 16)", "#2c7fb8"),
           ("gb200", "GB200 NVL72 (900/IB50, domain 64)", "#7a0177"),
           ("nvl72", "H100+IB (NVLink4 450/IB50, island 8)", "#d95f0e")]
FABRICS = [f for f in FABRICS if f[0] in mk]

# ---- Fig 1: headline breakdown ----
fig, ax = plt.subplots(figsize=(9, 5))
x = np.arange(len(MBS)); nF = len(FABRICS); bw = 0.8 / nF
for i, (key, lab, col) in enumerate(FABRICS):
    comp_h = [cp[mb] for mb in MBS]
    exp_h = [max(0.0, mk[key][mb] - cp[mb]) for mb in MBS]
    xs = x + (i - (nF - 1) / 2) * bw
    ax.bar(xs, comp_h, bw, color=col, alpha=0.4)
    ax.bar(xs, exp_h, bw, bottom=comp_h, color=col, label=f"{lab}: exposed comm")
    for xi, mb in zip(xs, MBS):
        ax.text(xi, mk[key][mb] + 4, f"{mk[key][mb]:.0f}", ha="center", fontsize=8)
ax.bar([], [], color="grey", alpha=0.4, label="compute (critical path, fabric-independent)")
ax.set_xticks(x); ax.set_xticklabels([f"mb={m}" for m in MBS])
ax.set_ylabel("per-layer iteration time (ms)")
ax.set_title("mixtral8x22B fully-measured (128 GPU, dp2·tp8·ep8)\n"
             "per-layer makespan = compute + exposed communication  (×56 layers for a step)")
ax.legend(fontsize=8, loc="upper left"); ax.grid(axis="y", ls=":", alpha=0.5)
fig.tight_layout(); fig.savefig(f"{FP}/mixtral_fabric_breakdown.png", dpi=150)
print("wrote mixtral_fabric_breakdown.png")

# ---- Fig 2: compute composition on critical path ----
cats = ["attention", "FFN/proj (Dense)", "softmax", "MoE router", "other"]
colors = ["#41b6c4", "#225ea8", "#a1dab4", "#fe9929", "#bdbdbd"]
fig2, ax2 = plt.subplots(figsize=(7.5, 5))
bottom = np.zeros(len(MBS))
for c, col in zip(cats, colors):
    h = [comp[mb].get(c, 0.0) for mb in MBS]
    ax2.bar(x, h, 0.6, bottom=bottom, label=c, color=col); bottom += np.array(h)
for xi, mb in zip(x, MBS):
    ax2.text(xi, cp[mb] + 1, f"{cp[mb]:.0f} ms", ha="center", fontsize=8)
ax2.set_xticks(x); ax2.set_xticklabels([f"mb={m}" for m in MBS])
ax2.set_ylabel("compute critical-path time (ms)")
ax2.set_title("mixtral8x22B — per-layer compute composition (critical path)")
ax2.legend(fontsize=8); ax2.grid(axis="y", ls=":", alpha=0.5)
fig2.tight_layout(); fig2.savefig(f"{FP}/mixtral_compute_composition.png", dpi=150)
print("wrote mixtral_compute_composition.png")

# ---- Fig 3: inter-panel BW sweep (optional) ----
ibw_csv = f"{FP}/mixtral_inter_bw_sweep.csv"
if os.path.exists(ibw_csv):
    data = defaultdict(list)  # mb -> [(ibw, ms)]
    with open(ibw_csv) as f:
        for r in csv.DictReader(f):
            data[int(r["mb"])].append((float(r["inter_bw"]), float(r["makespan_ms"])))
    fig3, ax3 = plt.subplots(figsize=(8, 5))
    for mb in sorted(data):
        pts = sorted(data[mb]); xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        ax3.plot(xs, ys, "o-", label=f"mb={mb}")
        ax3.axhline(cp[mb], ls=":", color="grey", alpha=0.4)
    ax3.axvline(50, ls="--", color="#d95f0e", alpha=0.7); ax3.text(52, ax3.get_ylim()[1]*0.9, "NVL72 IB 50", color="#d95f0e", fontsize=8)
    ax3.axvline(512, ls="--", color="#2c7fb8", alpha=0.7); ax3.text(440, ax3.get_ylim()[1]*0.82, "glass 512", color="#2c7fb8", fontsize=8, ha="right")
    ax3.set_xlabel("inter-panel optical BW (GB/s)  [intra fixed 512, panel 16]")
    ax3.set_ylabel("per-layer makespan (ms)")
    ax3.set_title("mixtral8x22B — sensitivity to inter-panel optical bandwidth\n"
                  "(dotted = compute floor; knee shows where the step stops being inter-panel-bound)")
    ax3.legend(fontsize=9); ax3.grid(ls=":", alpha=0.5)
    fig3.tight_layout(); fig3.savefig(f"{FP}/mixtral_inter_bw_sweep.png", dpi=150)
    print("wrote mixtral_inter_bw_sweep.png")
else:
    print("(inter-bw CSV not found yet, skipping Fig 3)")

print("\nmb   compute_cp   glass_mk  glass_exp   nvl72_mk  nvl72_exp   speedup(nvl72/glass)")
for mb in MBS:
    g, n = mk["glass"][mb], mk["nvl72"][mb]
    print(f"{mb:<4} {cp[mb]:9.1f}   {g:8.1f}  {g-cp[mb]:8.1f}   {n:8.1f}  {n-cp[mb]:8.1f}   {n/g:6.2f}x")
