#!/usr/bin/env python3
"""COMPACT paper thermal figure (one figure*, 3 panels): the whole honest thermal story.
  (a) 3D panel thermal (glass)  -> full-package FEASIBILITY (16 hotspots + coolant gradient)
  (b) glass vs Si tuning eff.    -> glass's genuine thermal ASSET (1.43x, -30% trim power)
  (c) ring-heater field glass|Si -> the MECHANISM (insulating glass confines the heater heat)
Reads panel_plane_glass.csv, thermal_tuning.csv, heatmap_glass.csv, heatmap_si.csv."""
import csv, os
import numpy as np
from scipy.interpolate import griddata
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.tri as mtri
from matplotlib.gridspec import GridSpec

HERE = os.path.dirname(os.path.abspath(__file__))
def P(n): return os.path.join(HERE, n)
plt.rcParams.update({"font.size": 10.5, "axes.titlesize": 11, "axes.labelsize": 10})

fig = plt.figure(figsize=(13.5, 4.4))
gs = GridSpec(1, 3, width_ratios=[1.15, 0.9, 1.15], wspace=0.28)

# ---- (a) 3D panel thermal (glass) -------------------------------------------
axa = fig.add_subplot(gs[0], projection="3d")
x, y, t = [], [], []
for a in csv.reader(open(P("panel_plane_glass.csv"))):
    if len(a) < 3: continue
    try: xx, yy, tt = map(float, a[:3])
    except ValueError: continue
    x.append(xx*1e3); y.append(yy*1e3); t.append(tt)
x, y, t = map(np.array, (x, y, t))
gx = np.linspace(x.min(), x.max(), 150); gy = np.linspace(y.min(), y.max(), 150)
GX, GY = np.meshgrid(gx, gy); GT = np.nan_to_num(griddata((x, y), t, (GX, GY)), nan=t.min())
axa.plot_surface(GX, GY, GT, cmap="inferno", rcount=140, ccount=140, linewidth=0, antialiased=True)
axa.set_xlabel("x [mm]", labelpad=1); axa.set_ylabel("y [mm]", labelpad=1)
axa.set_zlabel("°C", labelpad=1); axa.view_init(elev=34, azim=-54); axa.set_box_aspect((1,1,0.5))
axa.tick_params(pad=0, labelsize=8)
axa.set_title(f"(a) Full-panel 3D thermal (16 GPUs)\ndie {t.min():.0f}-{t.max():.0f}°C: feasible")

# ---- (b) glass vs Si tuning efficiency --------------------------------------
axb = fig.add_subplot(gs[1])
tr = {int(float(r["matflag"])): r for r in csv.DictReader(open(P("thermal_tuning.csv")))}
geff, seff = float(tr[1]["eff_KperW"]), float(tr[0]["eff_KperW"])
gpw, spw = float(tr[1]["ptune_total_W"]), float(tr[0]["ptune_total_W"])
axb.bar([0,1], [geff, seff], color=["#2c7fb8", "#d95f0e"], width=0.6)
for i,v in enumerate([geff,seff]): axb.text(i, v+1, f"{v:.0f}", ha="center", fontsize=10)
axb.set_xticks([0,1]); axb.set_xticklabels(["Glass", "Silicon"])
axb.set_ylabel("heater efficiency [K/W]")
axb.set_title(f"(b) Tuning efficiency\nglass {geff/seff:.2f}× → {100*(1-gpw/spw):.0f}% less trim power")
axb.grid(axis="y", ls=":", alpha=.5)

# ---- (c) ring-heater field glass | Si (mechanism) ---------------------------
axc = fig.add_subplot(gs[2])
def loadfield(fn):
    X, Zz, T = [], [], []
    for a in csv.reader(open(P(fn))):
        if len(a) < 3: continue
        try: xx, zz, tt = map(float, a[:3])
        except ValueError: continue
        X.append(xx*1e6); Zz.append(zz*1e6); T.append(tt-105.0)
    return np.array(X), np.array(Zz), np.array(T)
gX, gZ, gT = loadfield("heatmap_glass.csv"); sX, sZ, sT = loadfield("heatmap_si.csv")
vmax = max(gT.max(), sT.max())
# glass on left half, Si mirrored on right half of the panel for a split view
XCg = gX.max()/2; XCs = sX.max()/2
mg = gX <= XCg; ms = sX >= XCs
Xc = np.concatenate([gX[mg], sX[ms] - XCs + XCg])
Zc = np.concatenate([gZ[mg], sZ[ms]]); Tc = np.concatenate([gT[mg], sT[ms]])
tri = mtri.Triangulation(Xc, Zc)
cf = axc.tricontourf(tri, Tc, levels=np.linspace(0, vmax, 22), cmap="inferno")
axc.axvline(XCg, color="w", lw=1.2, ls="--")
axc.text(XCg*0.5, gZ.max()*0.95, "glass", color="w", ha="center", fontsize=9)
axc.text(XCg*1.5, gZ.max()*0.95, "silicon", color="w", ha="center", fontsize=9)
axc.set_xlabel("x [µm]"); axc.set_ylabel("z [µm]")
axc.set_title(f"(c) Ring-heater field: glass confines heat\n(peak +{gT.max():.1f} vs +{sT.max():.1f} K)")
cb = fig.colorbar(cf, ax=axc, fraction=0.046, pad=0.03); cb.set_label("ΔT [K]")

fig.savefig(P("fig_thermal_compact.png"), dpi=300, bbox_inches="tight")
print("wrote fig_thermal_compact.png")
