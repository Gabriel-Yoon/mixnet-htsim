#!/usr/bin/env python3
"""fig_thermal_panel: steady-state PIC-plane temperature of the 4x4 glass panel.

Input : experiments/results/thermal/panel_plane_{glass,si}.csv  (x[m], y[m], T[C]) -- /POST1 plane cut
        experiments/results/thermal/panel_tiles_{glass,si}.csv  (per-tile peaks, BCs, source_rth)
Output: <OUT>/thermal_panel_steady.png   (copy to DATE_2027_GlassPhotonics/figs/fig_thermal_panel.png)
Chain : thermal_panel_map_body.inp (die-only gate vs panhq .db) -> run_panel_map.sh -> .rth -> extract (b0be742/d734171) -> here.
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
ap.add_argument("--plane", default="panel_plane_glass_map1p15_h70k.csv", help="PIC-plane cut (x,y,T)")
ap.add_argument("--plane-si", default="panel_plane_si_map1p15_h70k.csv")
ap.add_argument("--tiles", default="panel_map_tiles.csv", help="per-tile CSV with variant column")
ap.add_argument("--variant", default="design_map_1p15")
ap.add_argument("--variant-si", default="design_map_1p15_si")
a = ap.parse_args()

def load_plane(fname):
    d = np.loadtxt(os.path.join(a.res, fname), delimiter=",")
    return d[:, 0] * 1e3, d[:, 1] * 1e3, d[:, 2]  # mm

def load_tiles(variant):
    with open(os.path.join(a.res, a.tiles)) as f:
        rows = [r for r in csv.DictReader(f) if r["variant"] == variant]
    assert rows, f"no rows for variant {variant}"
    bc = rows[0]
    peaks = {(int(r["tile_i"]), int(r["tile_j"])): float(r["pic_max_C"]) for r in rows}
    return peaks, bc

x, y, T = load_plane(a.plane)
peaks_g, bc = load_tiles(a.variant)
peaks_s, _ = load_tiles(a.variant_si)
L = x.max()
n = 4
pitch = L / n

fig, ax = plt.subplots(figsize=(3.4, 3.1), dpi=200)
tri = mtri.Triangulation(y, x)  # tile_i (coolant axis) runs along y in the cut; draw it left->right
levels = np.linspace(55, 140, 35)
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
cb = fig.colorbar(cf, ax=ax, fraction=0.046, pad=0.03, ticks=[60, 80, 100, 120, 140])
cb.ax.tick_params(labelsize=7); cb.set_label("PIC-plane T (°C)", fontsize=7)
gmax = max(peaks_g.values()); smax = max(peaks_s.values())
pic_w = sorted({float(r) for r in [bc["pic_w"]]})
ax.set_title(f"glass: PIC peak {gmax:.1f} °C  (Si control {smax:.1f})\n"
             f"700 W/die, PIC 14–58 W by tile ({bc['pj_bit']} pJ/bit), h={int(float(bc['hcp']))//1000}k W/m²K",
             fontsize=7.5)
fig.tight_layout(pad=0.3)
os.makedirs(a.out, exist_ok=True)
outp = os.path.join(a.out, "thermal_panel_steady.png")
fig.savefig(outp)
print("wrote", outp, "| glass peak", gmax, "| si peak", smax, "| variant", a.variant, "| bc_source", bc["bc_source"])
