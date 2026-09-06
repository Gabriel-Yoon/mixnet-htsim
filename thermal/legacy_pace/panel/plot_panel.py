#!/usr/bin/env python3
"""Full 4x4 panel thermal maps (ANSYS): package-scale gradient + per-tile.
  fig_panel_heatmap.png : PIC-layer top-view temperature map of the whole panel
                          (shows the center-hot package gradient and the 4x4 tile pattern).
  fig_panel_tiles.png   : per-tile peak temperature grid + per-tile ring-array gradient.
Reads panel_plane_<mat>.csv (x,y,T) and panel_tiles_<mat>.csv (ti,tj,pic_max,pic_min,pic_dT,die_max)."""
import csv, os, sys
import numpy as np
from scipy.interpolate import griddata
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
def P(n): return os.path.join(HERE, n)
MAT = sys.argv[1] if len(sys.argv) > 1 else "glass"
MM = 1e3

# ---- top-view panel heatmap -------------------------------------------------
x, y, t = [], [], []
for a in csv.reader(open(P(f"panel_plane_{MAT}.csv"))):
    if len(a) < 3: continue
    try: xx, yy, tt = map(float, a[:3])
    except ValueError: continue
    x.append(xx*MM); y.append(yy*MM); t.append(tt)
x, y, t = map(np.array, (x, y, t))
gx = np.linspace(x.min(), x.max(), 240); gy = np.linspace(y.min(), y.max(), 240)
GX, GY = np.meshgrid(gx, gy)
GT = griddata((x, y), t, (GX, GY), method="linear")

fig, ax = plt.subplots(figsize=(6.6, 5.6))
pc = ax.pcolormesh(GX, GY, GT, cmap="inferno", shading="auto")
cb = fig.colorbar(pc, ax=ax); cb.set_label("PIC-layer temperature  [C]")
ax.set_aspect("equal"); ax.set_xlabel("x  [mm]"); ax.set_ylabel("y  [mm]")
ax.set_title(f"4x4 glass panel (16 GPUs), PIC-layer temperature\n"
             f"package gradient {t.min():.0f}-{t.max():.0f} C; coolant flows +x -> outlet-side tiles run hottest")
fig.tight_layout(); fig.savefig(P(f"fig_panel_heatmap_{MAT}.png"), dpi=200)
print(f"wrote fig_panel_heatmap_{MAT}.png  (PIC {t.min():.1f}-{t.max():.1f} C, span {t.max()-t.min():.1f} K)")

# ---- per-tile grids ---------------------------------------------------------
rows = [r for r in csv.reader(open(P(f"panel_tiles_{MAT}.csv"))) if len(r) >= 6]
NX = int(max(float(r[0]) for r in rows)) + 1
pic_max = np.zeros((NX, NX)); pic_dT = np.zeros((NX, NX)); die_max = np.zeros((NX, NX))
for r in rows:
    ti, tj = int(float(r[0])), int(float(r[1]))
    pic_max[tj, ti] = float(r[2]); pic_dT[tj, ti] = float(r[4]); die_max[tj, ti] = float(r[5])

fig, axs = plt.subplots(1, 2, figsize=(11, 4.8))
for ax, M, ttl, lab in [(axs[0], die_max, "per-tile die peak temperature", "die peak [C]"),
                        (axs[1], pic_dT, "per-tile ring-array gradient", "PIC dT [K]")]:
    im = ax.imshow(M, origin="lower", cmap="inferno")
    for i in range(NX):
        for j in range(NX):
            ax.text(j, i, f"{M[i,j]:.0f}", ha="center", va="center",
                    color="w" if M[i,j] < (M.max()+M.min())/2 else "k", fontsize=10)
    ax.set_xticks(range(NX)); ax.set_yticks(range(NX))
    ax.set_xlabel("tile column"); ax.set_ylabel("tile row"); ax.set_title(ttl)
    cb = fig.colorbar(im, ax=ax, fraction=0.046); cb.set_label(lab)
fig.suptitle(f"4x4 panel per-tile summary ({MAT}): coolant warms along +x, so outlet-column tiles "
             f"run ~{die_max.max()-die_max.min():.0f} K hotter; per-tile ring gradient ~{pic_dT.mean():.0f} K",
             fontsize=10)
fig.tight_layout(rect=[0,0,1,0.95]); fig.savefig(P(f"fig_panel_tiles_{MAT}.png"), dpi=200)
print(f"wrote fig_panel_tiles_{MAT}.png  (die {die_max.min():.0f}-{die_max.max():.0f} C, "
      f"tile-to-tile span {die_max.max()-die_max.min():.0f} K)")
