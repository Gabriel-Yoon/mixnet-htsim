#!/usr/bin/env python3
"""fig_thermal_panel: steady-state PIC-plane temperature of the 4x4 glass panel.

Input : experiments/results/thermal/panel_plane_{glass,si}.csv  (x[m], y[m], T[C]) -- /POST1 plane cut
        experiments/results/thermal/panel_tiles_{glass,si}.csv  (per-tile peaks, BCs, source_rth)
Output: <OUT>/thermal_panel_steady.png   (copy to DATE_2027_GlassPhotonics/figs/fig_thermal_panel.png)
Chain : thermal_panel_body.inp -> run_panel_hq.sh -> panhq_{glass,si}.rth -> extract (0f757db) -> here.
Usage : python3 plot_thermal_panel.py [--res DIR] [--out DIR]
"""
import argparse, csv, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.tri as mtri

ap = argparse.ArgumentParser()
ap.add_argument("--res", default=os.path.join(os.path.dirname(__file__), "..", "..", "experiments", "results", "thermal"))
ap.add_argument("--out", default=os.environ.get("OUT", "."))
a = ap.parse_args()

def load_plane(sub):
    d = np.loadtxt(os.path.join(a.res, f"panel_plane_{sub}.csv"), delimiter=",")
    return d[:, 0] * 1e3, d[:, 1] * 1e3, d[:, 2]  # mm

def load_tiles(sub):
    with open(os.path.join(a.res, f"panel_tiles_{sub}.csv")) as f:
        rows = list(csv.DictReader(f))
    bc = rows[0]
    peaks = {(int(r["tile_i"]), int(r["tile_j"])): float(r["pic_max_C"]) for r in rows}
    return peaks, bc

x, y, T = load_plane("glass")
peaks_g, bc = load_tiles("glass")
peaks_s, _ = load_tiles("si")
L = x.max()
n = 4
pitch = L / n

fig, ax = plt.subplots(figsize=(3.4, 3.1), dpi=200)
tri = mtri.Triangulation(y, x)  # tile_i (coolant axis) runs along y in the cut; draw it left->right
levels = np.linspace(55, 120, 27)
cf = ax.tricontourf(tri, T, levels=levels, cmap="inferno", extend="both")
for k in range(1, n):
    ax.axhline(k * pitch, color="w", lw=0.4, alpha=0.6)
    ax.axvline(k * pitch, color="w", lw=0.4, alpha=0.6)
for (i, j), tp in peaks_g.items():
    ax.text((i + 0.5) * pitch, (j + 0.5) * pitch, f"{tp:.0f}", ha="center", va="center",
            fontsize=6.5, color="w" if tp < 100 else "k", fontweight="bold")
ax.set_xlim(0, L); ax.set_ylim(0, L); ax.set_aspect("equal")
ax.set_xticks([]); ax.set_yticks([])
ax.set_xlabel("coolant flow  →  (inlet 55 °C, outlet 75 °C)", fontsize=7, labelpad=2)
cb = fig.colorbar(cf, ax=ax, fraction=0.046, pad=0.03, ticks=[60, 80, 100, 120])
cb.ax.tick_params(labelsize=7); cb.set_label("PIC-plane T (°C)", fontsize=7)
gmax = max(peaks_g.values()); smax = max(peaks_s.values())
ax.set_title(f"glass: PIC peak {gmax:.1f} °C  (Si control {smax:.1f})\n"
             f"{bc['p_gpu_W']} W/tile, PIC all-lit, h={int(bc['hcp_W_m2K'])//1000}k W/m²K",
             fontsize=7.5)
fig.tight_layout(pad=0.3)
os.makedirs(a.out, exist_ok=True)
outp = os.path.join(a.out, "thermal_panel_steady.png")
fig.savefig(outp)
print("wrote", outp, "| glass peak", gmax, "| si peak", smax, "| source", bc["source_rth"])
