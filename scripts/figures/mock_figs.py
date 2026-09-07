#!/usr/bin/env python3
"""MOCK renders of the result figures (R1 cliff, R3 waterfall, R4 buffer-vs-tail) from the numbers
in hand on 2026-09-06, to settle the DESIGN before the final rows land. Every panel is stamped
MOCK; provisional numbers are hollow markers. Not a paper input."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import paper_style as ps
import matplotlib; matplotlib.use("Agg"); import matplotlib.ticker
import matplotlib.pyplot as plt
import numpy as np
ps.apply()
OUT = os.environ.get("OUT", ".")

def stamp(ax):
    ax.text(0.99, 0.02, "MOCK — design only", transform=ax.transAxes, ha="right", va="bottom", fontsize=6, color="#b22222", alpha=0.8)

# ---------------- R1: the cliff ----------------
ep = [16, 32, 64]
glass_pm   = [86.750, 92.323, None]          # port map (EP32 provisional: relay=1)
glass_mesh = [86.749, 186.383, 229.042]
nvl_pkt    = [130.797, None, None]
nvl_isl    = [83.499, 64.139, 88.378]
hgx_isl    = [145.497, 164.522, 493.707]
prov = {("glassfb", 32)}
fig = plt.figure(figsize=(ps.DBL_W, 2.5))
gs = fig.add_gridspec(1, 3, width_ratios=[1.25, 1, 1], wspace=0.35)
ax = fig.add_subplot(gs[0])
def line(ax, name, ys, **kw):
    pts = [(e, y) for e, y in zip(ep, ys) if y is not None]
    st = ps.style_line(name); st.update(kw)
    ax.plot([p[0] for p in pts], [p[1] for p in pts], **st)
    for e, y in pts:
        if (name, e) in prov: ax.plot(e, y, marker=st["marker"], markerfacecolor="white", color=st["color"], linestyle="none", markersize=5)
line(ax, "hgx8", hgx_isl); line(ax, "nvl64", nvl_isl)
line(ax, "glassfb_mesh", glass_mesh); line(ax, "nvl64_pkt", nvl_pkt); line(ax, "glassfb", glass_pm, linewidth=1.8)
ax.set_xscale("log", base=2); ax.set_yscale("log"); ax.set_xticks(ep); ax.set_xticklabels(["16\nLLaMA-MoE", "32\nLLaMA-MoE", "64\nQwen-MoE"])
ax.set_yticks([60, 100, 200, 400]); ax.set_yticklabels(["60", "100", "200", "400"]); ax.yaxis.set_minor_formatter(matplotlib.ticker.NullFormatter())
ax.set_xlabel("expert-parallel degree (model per point)"); ax.set_ylabel("iteration time (ms)")
for x, c, t in ((16, ps.COL["glassfb"], "panel"), (64, ps.COL["nvl64"], "NVL domain")):
    ax.axvline(x, color=c, lw=0.6, ls=":", alpha=0.7); ax.text(x, 470, t, color=c, fontsize=6, ha="center", va="bottom")
ax.axvline(8, color=ps.COL["hgx8"], lw=0.6, ls=":", alpha=0.7)
ax.legend(loc="lower right", ncol=1, handlelength=2.2, fontsize=5.6, bbox_to_anchor=(1.0, 0.0))
ax.text(32, 92.3*1.12, "relay=1", fontsize=5.5, color=ps.COL["glassfb"], ha="center")
stamp(ax)

# ---------------- R3: configuration waterfall at EP=32 ----------------
ax = fig.add_subplot(gs[1])
steps = [("mesh\n(submitted)", 186.383, ps.COL["glassfb_mesh"]),
         ("+port\nmap", 92.323, ps.COL["glassfb"]),
         ("+dim-order\nrelay", np.nan, ps.COL["glassfb"]),
         ("+hier.\nA2A", np.nan, ps.COL["glassfb_hier"])]
xs = np.arange(len(steps))
for i, (lab, v, c) in enumerate(steps):
    if np.isnan(v):
        ax.bar(i, 92.323, color="white", edgecolor=c, hatch="///", lw=0.8); ax.text(i, 92.323*1.05, "pending", ha="center", fontsize=6, color=c)
    else:
        ax.bar(i, v, color=c); ax.text(i, v*1.03, f"{v:.0f}", ha="center", fontsize=6.5)
ax.axhline(64.139, color=ps.COL["nvl64"], ls="--", lw=0.9); ax.text(3.45, 64.139*1.04, "NVL-64 bound 64", color=ps.COL["nvl64"], fontsize=6, ha="right")
ax.axhline(130.8, color=ps.COL["nvl64_pkt"], ls="-", lw=0.9, alpha=0.6); ax.text(3.45, 130.8*1.04, "NVL-64 queued (EP16) 131", color=ps.COL["nvl64_pkt"], fontsize=6, ha="right")
ax.set_xticks(xs); ax.set_xticklabels([s[0] for s in steps], fontsize=6); ax.set_ylabel("EP=32 iteration (ms)"); ax.set_ylim(0, 215)
stamp(ax)

# ---------------- R4: buffer vs tail (NVL-64 k sweep, final) ----------------
ax = fig.add_subplot(gs[2])
k = [4, 8, 16, 32, 64]; mk = [151.9, 147.1, 281.1, 130.8, 130.3]; rto = [6423, 1227, 166, 0, 0]; mx = [12.58, 12.72, 100.42, 6.74, 6.49]
ax.bar(range(5), mk, color=ps.COL["nvl64_pkt"], alpha=0.85, width=0.6)
for i, (m, r) in enumerate(zip(mk, rto)): ax.text(i, m + 6, f"{r}\nRTO", ha="center", fontsize=5.2, linespacing=0.9)
ax.set_xticks(range(5)); ax.set_xticklabels([f"{x}×" for x in k]); ax.set_xlabel("queue depth (× BDP)\nNVL-64, EP=16"); ax.set_ylabel("iteration (ms)"); ax.set_ylim(0, 330)
ax2 = ax.twinx(); ax2.plot(range(5), mx, color=ps.COL["tail"], marker="D", markersize=3.5, lw=1.2); ax2.set_ylabel("max FCT (ms)", color=ps.COL["tail"]); ax2.tick_params(axis="y", colors=ps.COL["tail"]); ax2.spines["right"].set_visible(True); ax2.grid(False)
stamp(ax)
fig.savefig(os.path.join(OUT, "mock_results_row1.png"), bbox_inches="tight")
print("wrote mock_results_row1.png")
