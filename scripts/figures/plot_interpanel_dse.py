#!/usr/bin/env python3
"""Two plots for the a2a-dominant fabric study (paper-config, seq1024 L4 proxies):
  1) interpanel_dse.png  — makespan vs INTER-panel optical BW (intra fixed 512) -> knee.
  2) a2a_topo_compare.png — makespan per topology/BW per model (compute + exposed comm)."""
import csv, os
from collections import defaultdict, OrderedDict
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
FLOOR = {"llamaMoE": 44.8, "mixtral8x7B": 105.9}

# ---- 1) inter-panel DSE ----
dse = {}
with open(f"{FP}/interpanel_dse.csv") as f:
    for r in csv.DictReader(f):
        if r["model"] == "llamaMoE":
            dse[int(r["inter_bw"])] = float(r["makespan_ms"])
xs = sorted(dse); ys = [dse[x] for x in xs]
fig, ax = plt.subplots(figsize=(8, 5))
ax.plot(xs, ys, "o-", color="#2c7fb8", lw=2, ms=7, label="glass-FB (intra fixed 512 GB/s)")
ax.axhline(FLOOR["llamaMoE"], ls=":", color="grey", label=f"compute floor ({FLOOR['llamaMoE']:.0f} ms)")
ax.axvline(50, ls="--", color="#d95f0e", alpha=.7); ax.text(52, max(ys)*.85, "IB 50", color="#d95f0e", fontsize=9)
ax.axvline(200, ls="--", color="#41ab5d", alpha=.8); ax.text(205, max(ys)*.7, "knee ~200", color="#41ab5d", fontsize=9)
ax.axvline(512, ls="--", color="#2c7fb8", alpha=.5); ax.text(420, max(ys)*.55, "intra 512", color="#2c7fb8", fontsize=9, ha="right")
ax.set_xlabel("inter-panel optical BW (GB/s)   [free design parameter]")
ax.set_ylabel("per-layer makespan (ms)")
ax.set_title("Inter-panel BW design-space exploration (llamaMoE, a2a-dominant TP1, 128 GPU)\n"
             "intra fixed 512 (WG-limited); knee ~200 GB/s -> inter-panel needs ~200, not 512")
ax.legend(); ax.grid(ls=":", alpha=.5)
fig.tight_layout(); fig.savefig(f"{FP}/interpanel_dse.png", dpi=150); print("wrote interpanel_dse.png")

# ---- 2) a2a topology comparison ----
mk = defaultdict(dict)
with open(f"{FP}/paper_a2a_topo_compare.csv") as f:
    for r in csv.DictReader(f):
        mk[r["model"]][r["topology"]] = float(r["makespan_ms"])
ORDER = [("fattree","Fat-tree @IB 50","#d95f0e"),
         ("glass_atIB","Glass-FB @50","#9ecae1"),
         ("fc","Fully-conn @50","#fdae61"),
         ("fattree_512","Fat-tree @512 (costly)","#fc4e2a"),
         ("glass_optical","Glass-FB optical @512","#2c7fb8")]
models = [m for m in FLOOR if m in mk]
fig2, ax2 = plt.subplots(figsize=(11, 5.5))
x = np.arange(len(models)); n = len(ORDER); bw = .8/n
for i,(k,lab,col) in enumerate(ORDER):
    comp = [FLOOR[m] for m in models]
    exp = [max(0., mk[m].get(k, FLOOR[m]) - FLOOR[m]) if k in mk[m] else 0 for m in models]
    xs2 = x + (i-(n-1)/2)*bw
    for j,m in enumerate(models):
        if k not in mk[m]: continue
        ax2.bar(xs2[j], comp[j], bw, color=col, alpha=.35)
        ax2.bar(xs2[j], exp[j], bw, bottom=comp[j], color=col, label=lab if j==0 else None)
        ax2.text(xs2[j], mk[m][k]+3, f"{mk[m][k]:.0f}", ha="center", fontsize=7)
ax2.bar([],[],color="grey",alpha=.35,label="compute floor")
ax2.set_xticks(x); ax2.set_xticklabels([f"{m}\n(floor {FLOOR[m]:.0f}ms)" for m in models])
ax2.set_ylabel("per-layer makespan (ms)")
ax2.set_title("a2a-dominant MoE: topology x bandwidth (paper-config TP1/TP4, seq1024 L4)\n"
              "glass-optical(512) matches fat-tree(512) AND beats normal fat-tree(IB 50) ~2.7x")
ax2.legend(fontsize=8, ncol=2); ax2.grid(axis="y", ls=":", alpha=.5)
fig2.tight_layout(); fig2.savefig(f"{FP}/a2a_topo_compare.png", dpi=150); print("wrote a2a_topo_compare.png")

print("\n-- summary --")
for m in models:
    ft=mk[m].get("fattree"); g=mk[m].get("glass_optical")
    if ft and g: print(f"  {m}: glass-optical {g:.0f} vs normal fat-tree(IB) {ft:.0f} -> {ft/g:.2f}x")
