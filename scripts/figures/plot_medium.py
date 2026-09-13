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

# --- (b) energy per iteration, glass vs copper-FB, from the paper's own hop-bytes (power_tiers.csv):
#     RDL tier at the Hsueh Table 1 electrical charge (energy_consts.py; unchanged by the medium), long-link tier at the copper bracket
#     (copper_energy.csv), inter-panel ports at the glass bracket (unchanged), static: glass laser+tuning
#     (5.3-9.12 W/panel), copper 0 (no laser or rings; retimer idle power is not charged, in copper's favour)
pt = {int(float(r["ep"])): r for r in csv.DictReader(open(os.path.join(RES, "power_tiers.csv"))) if r["system"] == os.environ.get("PRIMARY_GLASS", "glassfb_800")}
cue = {int(float(r["ep"])): r for r in csv.DictReader(open(os.path.join(RES, "copper_energy.csv")))}
def energy(ep):
    from energy_consts import glass_tiers, glass_static, J as JJ, ELEC_PJ, OPT_PJ
    r = pt[ep]; c = cue[ep]
    be, bo, bi = float(r["bytes_elec"]), float(r["bytes_opt"]), float(r["bytes_inter"])
    clo, chi = float(c["copper_pj_bit_lo"]), float(c["copper_pj_bit_hi"])
    assert abs(float(c["bytes_x_hops"]) - bo) / bo < 1e-6, "long-link bytes differ between the two tables"
    t = glass_tiers(r); st = glass_static(r)
    g_lo = sum(x[1] for x in t) + st[0]; g_hi = sum(x[2] for x in t) + st[1]
    # copper butterfly: same RDL and port tiers, long links at the copper bracket, no static term
    k_lo = JJ(be, ELEC_PJ[0]) + JJ(bo, clo) + JJ(bi, OPT_PJ[0])
    k_hi = JJ(be, ELEC_PJ[1]) + JJ(bo, chi) + JJ(bi, OPT_PJ[1])
    return (g_lo, g_hi), (k_lo, k_hi)

fig, (ax, axb) = plt.subplots(1, 2, figsize=(3.45, 1.4), dpi=200, gridspec_kw=dict(width_ratios=[1.25, 1], wspace=0.45))
for ep in EPS:
    g = q[("glass", ep)][0]
    pts = sorted([(rate, ms / g) for (arm, e), (ms, rate) in q.items() if e == ep and arm != "glass_pad400"])
    ax.plot([p for p, _ in pts], [v for _, v in pts], color=COL[ep], marker=MK[ep], ms=4, lw=1.2, label=f"EP={ep}", zorder=3)
    # (pad-only control not drawn at the user's request, 2026-09-12; it is stated in the text as 0.1-2%)
    last = pts[0]   # 50 GB/s point: label the copper-feasible penalty inline
    cu = q[("copper100", ep)][0] / g
    POS = {64: (112, cu + 0.16, "left"), 32: (80, 1.78, "left"), 16: (52, 1.05, "left")}   # clear of the curves
    px, py, ha = POS.get(ep, (112, cu, "left"))
    ax.text(px, py, f"{cu:.2f}×", fontsize=6.5, color=COL[ep], va="center", ha=ha)
ax.set_xscale("log"); ax.set_xticks([50, 100, 200, 384]); ax.set_xticklabels(["50", "100", "200", "384"]); ax.minorticks_off()
ax.set_xlabel("long-link rate (GB/s per direction)", fontsize=7.5)
ax.set_ylabel("iteration time,\nnormalized to Glass-FB", fontsize=7)
ax.tick_params(labelsize=7.5); ax.grid(axis="y", lw=0.4, alpha=0.4, zorder=0)
ax.spines["top"].set_visible(False); ax.spines["right"].set_visible(False)
h, l = ax.get_legend_handles_labels()
from matplotlib.lines import Line2D
ax.legend(h, l, frameon=False, fontsize=5.6, loc="upper right", ncol=1, handlelength=1.4, handletextpad=0.4, labelspacing=0.25)
ax.set_title("(a)", fontsize=7, loc="left", pad=2)
# (b)
xs = range(len(EPS)); w = 0.36
for i, ep in enumerate(EPS):
    (g_lo, g_hi), (k_lo, k_hi) = energy(ep)
    axb.bar(i - w / 2, g_hi, width=w, color="#c9dfe4", edgecolor="#2b6f7f", lw=0.6, zorder=3)
    axb.bar(i - w / 2, g_lo, width=w, color="#2b6f7f", zorder=4, label="Glass-FB" if i == 0 else None)
    axb.bar(i + w / 2, k_hi, width=w, color="#efd3c6", edgecolor="#c46a4a", lw=0.6, zorder=3)
    axb.bar(i + w / 2, k_lo, width=w, color="#c46a4a", zorder=4, label="copper-FB" if i == 0 else None)
    axb.text(i + 0.06, max(g_hi, k_hi) * 1.25, f"{k_lo/g_lo:.1f}–{k_hi/g_hi:.1f}×", ha="center", va="bottom", fontsize=5.6, color="#333")
    print(f"  EP={ep}: glass {g_lo:.1f}-{g_hi:.1f} J, copper-FB {k_lo:.1f}-{k_hi:.1f} J, ratio {k_lo/g_lo:.2f}-{k_hi/g_hi:.2f}")
axb.set_yscale("log"); axb.set_ylim(5, 30000)
axb.set_xticks(list(xs)); axb.set_xticklabels([f"EP={ep}" for ep in EPS], fontsize=6.5)
axb.set_ylabel("interconnect energy\nper iteration (J)", fontsize=7); axb.tick_params(labelsize=7.5)
axb.spines["top"].set_visible(False); axb.spines["right"].set_visible(False); axb.grid(axis="y", lw=0.4, alpha=0.4, zorder=0)
axb.legend(frameon=False, fontsize=5.6, loc="upper left", handlelength=1.2, handletextpad=0.4, labelspacing=0.25)
axb.set_title("(b)", fontsize=7, loc="left", pad=2)
fig.tight_layout(pad=0.3)
for ext in ("png", "pdf"):
    fig.savefig(os.path.join(OUT, f"fig_medium.{ext}"), bbox_inches="tight", pad_inches=0.02)
for ep in EPS:
    g = q[("glass", ep)][0]
    print(f"EP={ep}: " + ", ".join(f"{arm} {ms/g:.3f}" for (arm, e), (ms, _) in sorted(q.items(), key=lambda kv: -kv[1][1]) if e == ep))
print("wrote fig_medium.png")
