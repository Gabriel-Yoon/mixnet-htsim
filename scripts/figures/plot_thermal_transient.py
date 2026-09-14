#!/usr/bin/env python3
"""PIC temperature swing against the GPU power-fluctuation period (glass tile stack, calibrated
boundary h=200k, PIC 43 W, GPU square wave 50% duty 700 W <-> P_lo), from
experiments/results/thermal/tile_schedule.csv (delta_pp_K per period_s and p_lo_W, status=final),
with the idle->TDP step asymptote from tile_transient.csv (glass_stack_h200k_long) as the
long-period bound. Right axis: microring drift at 80 pm/K; reference line at one 100 GHz WDM
channel (0.8 nm = 10 K).

Env: THERMAL_RES (default experiments/results/thermal), OUT (default .).
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
RES = os.environ.get("THERMAL_RES", os.path.join(HERE, "..", "..", "experiments", "results", "thermal"))
OUT = os.environ.get("OUT", ".")
PM_PER_K = 80.0          # microring thermo-optic drift, pm/K (paper's Sec. design)
CHANNEL_PM = 800.0       # one 100 GHz WDM channel at 1550 nm, pm

sched = [r for r in csv.DictReader(open(os.path.join(RES, "tile_schedule.csv"))) if r["status"] == "final" and r["substrate"] == "glass"]
step = [r for r in csv.DictReader(open(os.path.join(RES, "tile_transient.csv"))) if r["variant"] == "glass_stack_h200k_long"]
step_K = float(step[0]["delta_T_K"]) if step else None
rise_s = float(step[0]["rise_10_90_s"]) if step else None

series = {}
for r in sched:
    plo = int(float(r["p_lo_W"]))
    if plo not in (0, 210): continue          # 350 W rows exist (tile_schedule.csv) but are not drawn
    series.setdefault(plo, []).append((float(r["period_s"]), float(r["delta_pp_K"])))
STYLE = {210: dict(color="#2b6f7f", marker="o", lw=1.2, label="GPU 700 / 210 W (30% floor)", zorder=4),
         0: dict(color="#3f4b56", marker="s", lw=1.1, ls=(0, (3, 2)), label="GPU 700 / 0 W (bound)", zorder=3),
         350: dict(color="#b7c5cc", marker="^", lw=0.9, ls=(0, (1, 1.5)), label="GPU 700 / 350 W", zorder=2)}

# First-order low-pass model of the tile stack, with its time constant taken from the measured
# idle->TDP step (10-90% rise = 2.197 tau): a 50%-duty square wave of period T between P_hi and
# P_lo gives a peak-to-peak swing  dT_step * (P_hi-P_lo)/P_hi * tanh(T / (4 tau)).  The ANSYS
# periodic points are drawn as markers on top; the curve is the model, not a fit.
import numpy as np
tau = rise_s / 2.197 if rise_s else None
T = np.logspace(-3, 0.6, 200)
fig, ax = plt.subplots(figsize=(3.45, 2.3), dpi=200)
for plo, pts in sorted(series.items(), key=lambda kv: -kv[0]):
    pts.sort()
    st = STYLE.get(plo, dict(color="#999", marker="x", label=f"P_lo={plo} W"))
    if len(pts) > 2:
        ax.plot([p for p, _ in pts], [d for _, d in pts], ls=st.get("ls", "-"), lw=st.get("lw", 1.0), color=st["color"], zorder=st.get("zorder", 3), label=st["label"])
    else:
        ax.scatter([], [], marker=st["marker"], color=st["color"], label=st["label"])
    ax.scatter([p for p, _ in pts], [d for _, d in pts], s=24, marker=st["marker"], color=st["color"], edgecolor="white", lw=0.5, zorder=5)
    last = max(pts)
    ax.annotate("%.1f K" % last[1], last, textcoords="offset points", xytext=(0, 6), ha="center", va="bottom", fontsize=6.5, color=st["color"])
    if tau and step_K:
        for p, d in pts:
            m = step_K * (700.0 - plo) / 700.0 * np.tanh(p / (4 * tau)); print("  model check P_lo=%d T=%.4g s: ANSYS %.1f K, model %.1f K" % (plo, p, d, m))
# (microbatch / iteration guide lines removed at the user's request, 2026-09-08)
# (no in-figure title: the caption carries it)
# (the idle-to-TDP step solve, 28.8 K at 0.3 s, is the 0 W series' own plateau; not drawn separately)
# (100 GHz channel line and label removed at the user's request, 2026-09-13)
ax.set_xscale("log"); ax.set_xlabel("GPU power fluctuation period", fontsize=8.5)
ax.set_xlim(0.001, 6.0); ax.set_xticks([0.001, 0.01, 0.1, 1.0]); ax.set_xticklabels(["1 ms", "10 ms", "100 ms", "1 s"]); ax.minorticks_off()
ax.set_ylabel("PIC swing, peak-to-peak (K)", fontsize=8.5)
ax.set_ylim(0, 33); ax.tick_params(labelsize=7.5)
ax2 = ax.twinx(); ax2.set_ylim(0, ax.get_ylim()[1] * PM_PER_K / 1000.0); ax2.set_ylabel("microring drift (nm) at 80 pm/K", fontsize=8.5); ax2.tick_params(labelsize=7.5)
ax2.spines["top"].set_visible(False); ax.spines["top"].set_visible(False)
ax.legend(frameon=False, fontsize=6.8, loc="upper left", handlelength=2.0)
ax.grid(axis="y", lw=0.4, alpha=0.4, zorder=0)
fig.tight_layout(pad=0.3)
for ext in ("png", "pdf"):
    fig.savefig(os.path.join(OUT, f"fig_thermal_transient.{ext}"))
for plo, pts in sorted(series.items()): print("  P_lo=%3d W:" % plo, ", ".join("%.4g s -> %.1f K" % (p, d) for p, d in sorted(pts)))
print("  step: %s K, rise %s s" % (step_K, rise_s)); print("wrote fig_thermal_transient.png")
