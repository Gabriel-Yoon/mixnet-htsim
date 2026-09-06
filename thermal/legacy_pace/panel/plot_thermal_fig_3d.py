#!/usr/bin/env python3
"""PUBLICATION 3D thermal figure: 4x4 glass panel (16 GPUs) PIC-layer temperature as a
3D surface, glass vs silicon side by side on a shared color scale, with a top-view contour
projected on the floor. Shows the 16 tile hotspots, the coolant-driven package gradient,
and the modest glass-vs-Si difference. Reads panel_plane_{glass,si}.csv (x,y,T).
  python3 plot_thermal_fig_3d.py            # both, side by side
  python3 plot_thermal_fig_3d.py glass      # glass only (single, larger)"""
import csv, os, sys
import numpy as np
from scipy.interpolate import griddata
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
def P(n): return os.path.join(HERE, n)
plt.rcParams.update({"font.size": 12, "axes.titlesize": 13, "axes.labelsize": 12})
MM = 1e3
CMAP = "inferno"

def load(m, n=180):
    x, y, t = [], [], []
    for a in csv.reader(open(P(f"panel_plane_{m}.csv"))):
        if len(a) < 3: continue
        try: xx, yy, tt = map(float, a[:3])
        except ValueError: continue
        x.append(xx*MM); y.append(yy*MM); t.append(tt)
    x, y, t = map(np.array, (x, y, t))
    gx = np.linspace(x.min(), x.max(), n); gy = np.linspace(y.min(), y.max(), n)
    GX, GY = np.meshgrid(gx, gy)
    GT = griddata((x, y), t, (GX, GY), method="linear")
    GT = np.nan_to_num(GT, nan=np.nanmin(t))
    return GX, GY, GT, t.min(), t.max()

mats = sys.argv[1:] if len(sys.argv) > 1 else ["glass", "si"]
data = {m: load(m) for m in mats}
vmin = min(d[3] for d in data.values()); vmax = max(d[4] for d in data.values())
titles = {"glass": "Glass substrate (k=1.2)", "si": "Silicon interposer (k=150)"}

fig = plt.figure(figsize=(6.4*len(mats), 5.6))
surf = None
for i, m in enumerate(mats):
    GX, GY, GT, tmn, tmx = data[m]
    ax = fig.add_subplot(1, len(mats), i+1, projection="3d")
    surf = ax.plot_surface(GX, GY, GT, cmap=CMAP, vmin=vmin, vmax=vmax,
                           rcount=170, ccount=170, linewidth=0, antialiased=True)
    # top-view contour projected on the floor
    ax.contourf(GX, GY, GT, zdir="z", offset=vmin-3, cmap=CMAP, levels=20, vmin=vmin, vmax=vmax, alpha=0.85)
    ax.set_zlim(vmin-3, vmax+2)
    ax.set_xlabel("x [mm]  (coolant flow →)", labelpad=6)
    ax.set_ylabel("y [mm]", labelpad=6)
    ax.set_zlabel("PIC temp [°C]", labelpad=4)
    ax.set_title(f"{titles.get(m, m)}\npeak {tmx:.0f} °C", fontsize=12)
    ax.view_init(elev=34, azim=-54)
    ax.set_box_aspect((1, 1, 0.5))
    ax.tick_params(pad=1)
cb = fig.colorbar(surf, ax=fig.axes, fraction=0.018, pad=0.02, shrink=0.62)
cb.set_label("PIC-layer temperature  [°C]")
fig.suptitle("Full-package ANSYS 3D thermal: 4×4 panel (16 GPUs). Sixteen tile hotspots on a "
             "coolant gradient;\nglass runs a few K hotter than silicon but stays in the die-junction band",
             fontsize=12.5)
fig.savefig(P("fig_thermal_3d.png"), dpi=300, bbox_inches="tight")
print("wrote fig_thermal_3d.png  (" + ", ".join(f"{m} {data[m][4]:.0f}C" for m in mats) + ")")
