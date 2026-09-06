#!/usr/bin/env python3
"""Iso-power comparison: fat-tree makespan vs its electrical link BW, with the glass-FB optical
point (512 GB/s @ 70W passive) overlaid. Electrical at 70W/GPU buys only ~50-100 GB/s/link
(SerDes ~5pJ/bit + active switches) vs optical 512 GB/s (1.15 pJ/bit, passive). So glass-FB wins
the iso-power comparison; fat-tree needs ~512 GB/s (~10x power) to merely match."""
import csv, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
FLOOR = 44.8

# fat-tree (llama) makespan at link BW: from isopower + a2a CSVs
ft = {50: 245.052, 100: 160.186, 200: 118.456, 512: 91.101}
glass = (512, 89.4)  # glass-FB optical @ 512 GB/s, 70W passive

xs = sorted(ft); ys = [ft[x] for x in xs]
fig, ax = plt.subplots(figsize=(8.5, 5.5))
ax.plot(xs, ys, "s-", color="#d95f0e", lw=2, ms=8, label="electrical fat-tree (non-blocking 1:1)")
ax.plot(glass[0], glass[1], "*", color="#2c7fb8", ms=22, label="glass-FB optical (512 GB/s, 70 W passive)")
ax.axhline(FLOOR, ls=":", color="grey", label=f"compute floor ({FLOOR:.0f} ms)")
# iso-power region (what 70W buys electrically: ~50-100 GB/s)
ax.axvspan(50, 100, color="#d95f0e", alpha=.12)
ax.text(70, max(ys)*.92, "iso-power\n(electrical @70W)", color="#a63603", fontsize=9, ha="center")
# guide: fat-tree must reach ~512 to match glass
ax.annotate("fat-tree needs ~512 GB/s\n(~10x power, infeasible electrically)\nto match glass-FB",
            xy=(512, 91), xytext=(150, 60), fontsize=8.5,
            arrowprops=dict(arrowstyle="->", color="grey"))
for x in xs: ax.text(x, ft[x]+5, f"{ft[x]:.0f}", ha="center", fontsize=8, color="#a63603")
ax.text(glass[0], glass[1]-12, f"{glass[1]:.0f} ms", ha="center", fontsize=9, color="#2c7fb8")
ax.set_xscale("log"); ax.set_xticks(xs); ax.set_xticklabels([str(x) for x in xs])
ax.set_xlabel("per-link bandwidth (GB/s)")
ax.set_ylabel("per-layer makespan (ms)")
ax.set_title("Iso-power fabric comparison (llamaMoE a2a-dominant, 128 GPU)\n"
             "at equal 70W, optical buys 512 GB/s vs electrical ~50-100 -> glass-FB 1.8-2.75x faster")
ax.legend(fontsize=9, loc="upper right"); ax.grid(ls=":", alpha=.5)
fig.tight_layout(); fig.savefig(f"{FP}/isopower_compare.png", dpi=150)
print("wrote isopower_compare.png")
print(f"  iso-power (50-100 GB/s): glass {glass[1]:.0f} vs fat-tree {ft[50]:.0f}-{ft[100]:.0f} -> "
      f"{ft[50]/glass[1]:.2f}-{ft[100]/glass[1]:.2f}x")
print(f"  even fat-tree@200 (>iso-power): {ft[200]/glass[1]:.2f}x slower than glass")
