#!/usr/bin/env python3
"""Panel-size design-space figure (htsim): WHY 4x4. Reads panel_dse_htsim.csv
(panel,grid,microbatch,makespan_ms,link_bw_gbs). Twin-axis:
  left  y  = iteration time (ms), one line per microbatch (a2a load)
  right y  = feasible per-link optical BW (GB/s), limited by the micro-bump WG budget
As the panel grows (4x4 -> 4x8 -> 8x8): (1) the WG/link budget forces THINNER links (right axis
down) AND (2) more 2-hop relay pairs add overhead -> iteration time RISES at every a2a load.
4x4 is the joint sweet spot (high per-link BW x low relay overhead), robust across microbatch.
No in-figure title (it goes in the filename, in parentheses)."""
import csv
from collections import defaultdict
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
plt.rcParams.update({"font.size": 13, "axes.labelsize": 15, "xtick.labelsize": 13,
                     "ytick.labelsize": 13, "legend.fontsize": 12})
rows = list(csv.DictReader(open(f"{FP}/panel_dse_htsim.csv")))
panels = sorted({int(r["panel"]) for r in rows})
grid = {int(r["panel"]): r["grid"] for r in rows}
bw   = {int(r["panel"]): float(r["link_bw_gbs"]) for r in rows}
by_mb = defaultdict(dict)
for r in rows:
    by_mb[int(r["microbatch"])][int(r["panel"])] = float(r["makespan_ms"])

fig, axL = plt.subplots(figsize=(8.8, 6.4))
xs = list(range(len(panels)))
cmap = {8:"#9ecae1", 16:"#4575b4", 32:"#08306b"}
for mb in sorted(by_mb):
    ys = [by_mb[mb].get(p) for p in panels]
    axL.plot(xs, ys, "o-", lw=2.8, ms=9, color=cmap.get(mb,"#4575b4"),
             label=f"microbatch {mb} (a2a load)", zorder=5)
axL.axvspan(-0.22, 0.22, color="#2c7fb8", alpha=0.10, zorder=0)
axL.set_xticks(xs); axL.set_xticklabels([f"{grid[p]}\n({p} GPU)" for p in panels])
axL.set_xlabel("glass-FB panel size  (scale-up domain)", labelpad=10)
axL.set_ylabel("iteration time (ms)  — lower is better", color="#08306b")
axL.tick_params(axis="y", labelcolor="#08306b")
axL.grid(axis="y", ls=":", alpha=.5)
axL.text(0, axL.get_ylim()[1]*0.96, "chosen\n4x4", ha="center", va="top",
         color="#225ea8", fontsize=14, fontweight="bold")

axR = axL.twinx()
axR.plot(xs, [bw[p] for p in panels], "s--", lw=2.4, ms=9, color="#d95f0e", label="feasible per-link BW")
axR.set_ylabel("feasible per-link optical BW (GB/s)\n(micro-bump WG budget)", color="#d95f0e")
axR.tick_params(axis="y", labelcolor="#d95f0e")
axR.set_ylim(0, max(bw.values())*1.3)
axR.annotate("bigger grid → higher degree\n→ fewer WG/link → thinner links",
             xy=(len(panels)-1, bw[panels[-1]]), xytext=(1.30, bw[panels[-1]]*0.30),
             fontsize=11.5, color="#b03000", ha="left",
             arrowprops=dict(arrowstyle="->", color="#d95f0e"))

# legend BELOW the axes so it never covers the curves
lines = axL.get_lines()[:len(by_mb)] + [axR.get_lines()[0]]
axL.legend(lines, [l.get_label() for l in lines], loc="upper center",
           bbox_to_anchor=(0.5, -0.22), ncol=2, frameon=False, columnspacing=2.5)

out = f"{FP}/panel_dse_htsim_(why-4x4-panel-size-sweet-spot).png"
fig.savefig(out, dpi=300, bbox_inches="tight")
print("wrote", out)
for mb in sorted(by_mb):
    print(f"  mb{mb}: " + "  ".join(f"{grid[p]}({p})={by_mb[mb].get(p)}" for p in panels))
