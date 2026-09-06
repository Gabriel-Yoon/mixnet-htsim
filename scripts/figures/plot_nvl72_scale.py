#!/usr/bin/env python3
"""Scale sweep (E5, reframed): glass-FB (design) vs REALIZABLE electrical fat-tree across GPU scale.
Reads all outputs/fabric_plots/nvl72_crossover_*.csv (columns: model,nodes,fabric,intra_bw,inter_bw,
panel,makespan_ps,makespan_ms) merged across per-TAG runs. Each model contributes one point at its
native GPU scale (nodes). Two panels:
  (A) absolute makespan (ms) vs GPU scale, one line per fabric.
  (B) glass advantage = fattree@100 / glass  (>1 = glass faster); shows whether the advantage holds
      as scale grows. gb200/h100 are intentionally absent (placement-sensitive; see script header).
No in-figure title (goes in the filename)."""
import csv, glob
from collections import defaultdict
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
plt.rcParams.update({"font.size": 13, "axes.labelsize": 15, "xtick.labelsize": 12,
                     "ytick.labelsize": 12, "legend.fontsize": 11})
COL = {"glass":"#2c7fb8","fattree100":"#d95f0e","fattree50":"#fdae61","flat100":"#41ab5d"}
LAB = {"glass":"Glass-FB (design)","fattree100":"Fat-tree @100 GB/s","fattree50":"Fat-tree @50 GB/s",
       "flat100":"flat / full-bisection @100"}

rows = []
for f in sorted(glob.glob(f"{FP}/nvl72_crossover_*.csv")):
    rows += list(csv.DictReader(open(f)))
# fabric -> {nodes: (model, ms)}   (last write wins per (fabric,nodes))
byf = defaultdict(dict)
for r in rows:
    ms = float(r["makespan_ms"])
    if ms <= 0: continue
    byf[r["fabric"]][int(r["nodes"])] = (r["model"], ms)

fig, (axA, axB) = plt.subplots(1, 2, figsize=(13.5, 5.6))
for fab in ["flat100","glass","fattree100","fattree50"]:
    if fab not in byf: continue
    xs = sorted(byf[fab]); ys = [byf[fab][x][1] for x in xs]
    axA.plot(xs, ys, "o-", color=COL[fab], lw=2.4, ms=8, label=LAB[fab])
axA.set_xscale("log", base=2); axA.set_yscale("log")
axA.set_xlabel("GPU scale (nodes)"); axA.set_ylabel("iteration time (ms)")
axA.grid(ls=":", alpha=.5, which="both"); axA.legend()
axA.set_title("(A) absolute makespan", fontsize=12)

# (B) glass advantage vs fat-tree@100
if "glass" in byf and "fattree100" in byf:
    xs = sorted(set(byf["glass"]) & set(byf["fattree100"]))
    adv = [byf["fattree100"][x][1] / byf["glass"][x][1] for x in xs]
    axB.plot(xs, adv, "D-", color="#2c7fb8", lw=2.6, ms=9)
    for x, a in zip(xs, adv):
        axB.annotate(f"{a:.2f}x\n{byf['glass'][x][0]}", (x, a), fontsize=8,
                     ha="center", va="bottom", color="#225ea8")
    axB.axhline(1.0, ls="--", color="grey", alpha=.7)
    axB.text(xs[0], 1.02, "glass faster ↑", color="#225ea8", fontsize=9)
axB.set_xscale("log", base=2)
axB.set_xlabel("GPU scale (nodes)"); axB.set_ylabel("glass speedup vs Fat-tree @100 (×)")
axB.grid(ls=":", alpha=.5, which="both")
axB.set_title("(B) glass advantage vs realizable fat-tree across scale", fontsize=12)

fig.tight_layout()
out = f"{FP}/scale_sweep_(glass-vs-electrical-fattree).png"
fig.savefig(out, dpi=300, bbox_inches="tight"); print("wrote", out)
for fab in byf:
    print(f"  {fab}: " + ", ".join(f"{n}({byf[fab][n][0]})={byf[fab][n][1]:.0f}" for n in sorted(byf[fab])))
