#!/usr/bin/env python3
"""Long-link rate sweep at the copper latency pad (medium ablation), from
experiments/results/paper/medium_ablation.csv (quotable rows only).

x: distance>=2 link rate per direction (384 = glass design point, 200 = rate point,
100 = copper-feasible, 50); y: iteration normalized to the glass design point at the same EP.
The pad-only control (glass 384 GB/s with the 400 ns pad) is drawn as a hollow marker at 384.
Hop classification is rate-invariant, so the sweep moves makespan only; no energy curve.

Env: RES (default experiments/results/paper), OUT (default .).
"""
import csv, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
try:
    sys.path.insert(0, os.path.dirname(__file__)); import paper_style as _ps; _ps.apply()
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.environ.get("RES", os.path.join(HERE, "..", "..", "experiments", "results", "paper"))
OUT = os.environ.get("OUT", ".")

rows = [r for r in csv.DictReader(open(os.path.join(RES, "medium_ablation.csv"))) if (r.get("quotable") or "").lower() == "yes"]
q = {}
for r in rows:
    q[(r["arm"], int(float(r["ep"])))] = (float(r["makespan_ms"]), float(r["long_link_GBps"]))
EPS = sorted({ep for _, ep in q})
COL = {16: "#2b6f7f", 32: "#4b3f8f", 64: "#c46a4a"}
MK = {16: "o", 32: "s", 64: "^"}

fig, ax = plt.subplots(figsize=(3.45, 1.35), dpi=200)
for ep in EPS:
    g = q[("glass", ep)][0]
    pts = sorted([(rate, ms / g) for (arm, e), (ms, rate) in q.items() if e == ep and arm != "glass_pad400"])
    ax.plot([p for p, _ in pts], [v for _, v in pts], color=COL[ep], marker=MK[ep], ms=4, lw=1.2, label=f"EP={ep}", zorder=3)
    if ("glass_pad400", ep) in q:   # pad-only control: hollow marker at the design rate
        ax.scatter([384], [q[("glass_pad400", ep)][0] / g], s=30, marker=MK[ep], facecolor="white", edgecolor=COL[ep], lw=1.0, zorder=4)
    last = pts[0]   # 50 GB/s point: label the copper-feasible penalty inline
    cu = q[("copper100", ep)][0] / g
    ax.annotate(f"{cu:.2f}×", (100, cu), textcoords="offset points", xytext=(5, -2 if ep != 64 else 4), fontsize=6.5, color=COL[ep], va="center")
ax.axvline(100, color="#999", lw=0.6, ls=(0, (3, 2)), zorder=1)
ax.text(100, ax.get_ylim()[1] * 0.98, " copper-feasible", fontsize=5.8, color="#666", va="top", ha="left")
ax.set_xscale("log"); ax.set_xticks([50, 100, 200, 384]); ax.set_xticklabels(["50", "100", "200", "384\n(glass)"]); ax.minorticks_off()
ax.set_xlabel("distance-≥2 link rate (GB/s per direction)", fontsize=7.5)
ax.set_ylabel("iteration / glass", fontsize=7.5)
ax.tick_params(labelsize=7.5); ax.grid(axis="y", lw=0.4, alpha=0.4, zorder=0)
ax.spines["top"].set_visible(False); ax.spines["right"].set_visible(False)
h, l = ax.get_legend_handles_labels()
from matplotlib.lines import Line2D
h.append(Line2D([], [], marker="o", ls="", markerfacecolor="white", markeredgecolor="#555", label="glass, 400 ns pad")); l.append("glass, 400 ns pad")
ax.legend(h, l, frameon=False, fontsize=6.2, loc="upper right", ncol=2, handlelength=1.6, columnspacing=0.8)
fig.tight_layout(pad=0.3)
for ext in ("png", "pdf"):
    fig.savefig(os.path.join(OUT, f"fig_medium.{ext}"))
for ep in EPS:
    g = q[("glass", ep)][0]
    print(f"EP={ep}: " + ", ".join(f"{arm} {ms/g:.3f}" for (arm, e), (ms, _) in sorted(q.items(), key=lambda kv: -kv[1][1]) if e == ep))
print("wrote fig_medium.png")
