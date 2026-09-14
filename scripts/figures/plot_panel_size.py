#!/usr/bin/env python3
"""Panel size: iteration time of the 4x4 glass panel against two 64-GPU panels (8x8 flattened
butterfly, 8x8 electrical mesh) on the same task graphs, normalized to the 4x4 panel at each EP.
Quotable rows of experiments/results/paper/panel_dse.csv (EP 16/32/64; the 8x4 arm is not drawn,
by the user's decision of 2026-09-09). Env: RES, OUT."""
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
q = {}
for r in csv.DictReader(open(os.path.join(RES, "panel_dse.csv"))):
    if (r.get("quotable") or "").lower() == "yes":
        q[(r["grid"], r["topo"], int(float(r["ep"])))] = float(r["makespan_ms"])
EPS = [16, 32, 64]
ARMS = [(("4x4", "flattened_butterfly"), "4×4 FB (glass)", "#2b6f7f"),
        (("8x8", "flattened_butterfly"), "8×8 FB (glass)", "#8fbcc6"),
        (("8x8", "mesh"), "8×8 mesh (electrical)", "#c46a4a")]
fig, ax = plt.subplots(figsize=(3.45, 1.5), dpi=200)
w = 0.2
for k, (key, lab, col) in enumerate(ARMS):
    xs, ys = [], []
    for i, ep in enumerate(EPS):
        base = q[("4x4", "flattened_butterfly", ep)]
        v = q[(key[0], key[1], ep)] / base
        x = i + (k - 1) * w
        xs.append(x); ys.append(v)
        ax.text(x, v + 0.02, f"{v:.2f}", ha="center", va="bottom", fontsize=5.6, color="#333")
    ax.bar(xs, ys, width=w, color=col, label=lab, zorder=3)
    print(lab, " ".join(f"EP{ep}={y:.3f}" for ep, y in zip(EPS, ys)))
ax.set_xticks(range(len(EPS))); ax.set_xticklabels([f"EP={e}" for e in EPS], fontsize=7)
ax.set_ylim(0, 1.95); ax.set_yticks([0, 0.5, 1.0, 1.5])
ax.set_ylabel("iteration time,\nnormalized to 4×4", fontsize=7)
ax.tick_params(labelsize=7); ax.grid(axis="y", lw=0.4, alpha=0.4, zorder=0)
ax.spines["top"].set_visible(False); ax.spines["right"].set_visible(False)
ax.legend(frameon=False, fontsize=5.8, loc="upper left", ncol=3, handlelength=1.1, columnspacing=0.7, handletextpad=0.35)
fig.tight_layout(pad=0.3)
for ext in ("png", "pdf"):
    fig.savefig(os.path.join(OUT, f"fig_panel_size.{ext}"), bbox_inches="tight", pad_inches=0.02)
print("wrote fig_panel_size.png")
