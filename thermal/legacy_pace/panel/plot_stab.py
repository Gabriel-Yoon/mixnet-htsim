#!/usr/bin/env python3
"""Stabilization-feasibility figure (ANSYS transient): the microring PIC's thermal
response to a fluctuating GPU power (square wave idle<->TDP), swept over fluctuation
period. Left: time traces at representative periods. Right: ripple amplitude vs period
= the package thermal transfer function (low-pass) -> corner where fast fluctuations
start being filtered. Excursion is bounded (~tuning range) and the fastest dynamics are
far slower than a kHz thermo-optic control loop -> the rings are stabilizable.
Reads stab_p*.csv (each: time_s, T_pic_C). File tags encode the period."""
import os, glob, re
import numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
def P(n): return os.path.join(HERE, n)
plt.rcParams.update({"font.size": 11})

def period_of(fn):
    m = re.search(r"stab_p([0-9p]+)\.csv", os.path.basename(fn))
    return float(m.group(1).replace("p", ".")) if m else None

def load(fn):
    t, v = [], []
    for line in open(fn):
        a = line.replace(",", " ").split()
        if len(a) < 2: continue
        try: tt, vv = float(a[0]), float(a[1])
        except ValueError: continue
        t.append(tt); v.append(vv)
    return np.array(t), np.array(v)

files = sorted(glob.glob(P("stab_p*.csv")), key=lambda f: period_of(f) or 0)
data = [(period_of(f), *load(f)) for f in files if period_of(f)]
data = [d for d in data if len(d[2]) > 3]

# ripple = peak-to-peak in the last 40% (steady portion)
per, rip = [], []
for pr, t, v in data:
    n0 = int(0.5*len(v)); seg = v[n0:]
    per.append(pr); rip.append(seg.max()-seg.min())
per, rip = np.array(per), np.array(rip)

fig, (ax, ax2) = plt.subplots(1, 2, figsize=(12.5, 4.7), gridspec_kw={"width_ratios":[1.4,1]})
# left: time traces for a few representative periods
show = [0.05, 0.5, 10.0]
cols = {0.05:"#2c7fb8", 0.5:"#7a0177", 10.0:"#d95f0e"}
for pr, t, v in data:
    if min(show, key=lambda s: abs(s-pr)) == pr and abs(min(show, key=lambda s: abs(s-pr))-pr) < 1e-6 or pr in show:
        tt = t - t.min()
        ax.plot(tt, v, "-", lw=1.6, color=cols.get(pr, "#888"), label=f"period {pr:g}s")
ax.set_xlabel("time [s]"); ax.set_ylabel("PIC (ring) temperature [°C]")
ax.set_title("PIC response to fluctuating GPU power (idle↔TDP)")
ax.grid(ls=":", alpha=.5); ax.legend(fontsize=9)

# right: ripple vs period (transfer function) — the low-pass
ax2.semilogx(per, rip, "o-", color="#2c7fb8", lw=2, ms=7)
plateau = rip[per >= 2].mean() if (per >= 2).any() else rip.max()
ax2.axhline(plateau, ls=":", color="#999")
ax2.text(per.min(), plateau*0.9, f"slow-limit ≈ {plateau:.1f} K\n(within ring tuning range)",
         fontsize=9, color="#555")
# mark half-amplitude corner
half = plateau/2
if (rip < half).any() and (rip >= half).any():
    # interpolate corner period
    idx = np.argsort(per)
    pc = np.interp(half, rip[idx], per[idx])
    ax2.axvline(pc, ls="--", color="#d95f0e")
    ax2.text(pc, half*1.1, f"corner ~{pc*1000:.0f} ms\n(fast fluctuations filtered)",
             fontsize=9, color="#b03000")
ax2.set_xlabel("GPU fluctuation period [s]"); ax2.set_ylabel("PIC temperature ripple [K]")
ax2.set_title("Thermal transfer function (package low-pass)")
ax2.grid(ls=":", alpha=.5, which="both")
fig.suptitle("Thermal stabilization is feasible: the ring excursion is bounded (≈ tuning range) and its "
             "fastest dynamics\n(tens of ms) are ~100x slower than a kHz thermo-optic control loop; "
             "sub-corner GPU fluctuations are filtered by the package", fontsize=10.5)
fig.tight_layout(rect=[0,0,1,0.9]); fig.savefig(P("fig_thermal_stab.png"), dpi=200)
print(f"wrote fig_thermal_stab.png  plateau~{plateau:.1f}K; " +
      ", ".join(f"{p:g}s={r:.2f}K" for p, r in zip(per, rip)))
