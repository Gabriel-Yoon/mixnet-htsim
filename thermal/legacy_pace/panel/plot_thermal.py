#!/usr/bin/env python3
"""Plot the glass-photonic FB package thermal results (ANSYS MAPDL output).
  T3  fig_thermal_sweep.png  : dT_array (ring gradient) vs TGV pitch, glass vs Si,
                               + trim-power axis; marks the feasible window.
  T2  fig_thermal_transient.png : PIC-center temperature vs time after a GPU power
                               step, glass vs Si -> glass low-passes the transient.
Reads thermal_steady.csv, transient_glass.csv, transient_si.csv (from run_thermal.sh)."""
import csv, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
def P(n): return os.path.join(HERE, n)

# ---- T3: steady sweep -------------------------------------------------------
rows = list(csv.DictReader(open(P("thermal_steady.csv"))))
def series(matflag):
    r = [x for x in rows if int(float(x["matflag"])) == matflag]
    r.sort(key=lambda x: float(x["pitch_um"]))
    return ([float(x["pitch_um"]) for x in r],
            [float(x["dT_array_K"]) for x in r],
            [float(x["ptrim_W"]) for x in r],
            [float(x["tpic_max_C"]) for x in r])

if rows:
    gp, gdt, gtr, gtm = series(1)   # glass
    sp, sdt, str_, stm = series(0)  # silicon
    fig, ax = plt.subplots(figsize=(6.2, 4.4))
    ax.plot(gp, gdt, "o-", color="#2c7fb8", lw=2.4, ms=7, label="Glass substrate (k=1.2)")
    ax.plot(sp, sdt, "s--", color="#d95f0e", lw=2.2, ms=7, label="Silicon interposer (k=150, control)")
    # feasible window: ring gradient below a tuning-budget threshold
    DT_MAX = 5.0
    ax.axhspan(0, DT_MAX, color="#2c7fb8", alpha=0.08)
    ax.axhline(DT_MAX, ls=":", color="#225ea8")
    ax.text(gp[0], DT_MAX*1.03, f"tuning-feasible (< {DT_MAX:.0f} K across array)",
            color="#225ea8", fontsize=9)
    ax.set_xlabel("TGV pitch  [um]  (denser -> more PIC heat extraction)")
    ax.set_ylabel("ring-array gradient  dT_array  [K]")
    ax.set_title("Package feasibility: ring-array gradient vs TGV pitch\n"
                 "glass keeps the microring array within tuning budget; silicon does not")
    ax.grid(ls=":", alpha=.5); ax.legend(fontsize=9)
    # secondary axis: implied thermo-optic trim power (glass)
    ax2 = ax.twinx()
    ax2.plot(gp, gtr, "^-", color="#41ab5d", lw=1.6, ms=6, alpha=.8, label="trim power (glass)")
    ax2.set_ylabel("thermo-optic trim power  [W]", color="#2e8b57")
    ax2.tick_params(axis="y", labelcolor="#2e8b57")
    fig.tight_layout(); fig.savefig(P("fig_thermal_sweep.png"), dpi=200)
    print("wrote fig_thermal_sweep.png")
    for pu, dt, tr, tm in zip(gp, gdt, gtr, gtm):
        print(f"  glass pitch{pu:>4.0f}um  dT_array={dt:5.2f}K  trim={tr:5.1f}W  T_pic_max={tm:5.1f}C")

# ---- T2: transient ----------------------------------------------------------
def load_tr(fn):
    if not os.path.exists(P(fn)): return None
    t, v = [], []
    for line in open(P(fn)):
        line = line.strip()
        if not line or line[0].isalpha(): continue
        a = line.split(",")
        if len(a) < 2: continue
        try:
            t.append(float(a[0]) - 30.0); v.append(float(a[1]))  # step at raw t=30 s
        except ValueError:
            continue
    return t, v

g = load_tr("transient_glass.csv"); s = load_tr("transient_si.csv")
if g or s:
    fig, ax = plt.subplots(figsize=(6.2, 4.4))
    if g:
        g0 = g[1][0]
        ax.plot([x for x in g[0] if x >= 0], [y - g0 for x, y in zip(*g) if x >= 0],
                "-", color="#2c7fb8", lw=2.6, label="Glass substrate")
    if s:
        s0 = s[1][0]
        ax.plot([x for x in s[0] if x >= 0], [y - s0 for x, y in zip(*s) if x >= 0],
                "--", color="#d95f0e", lw=2.2, label="Silicon interposer (control)")
    ax.set_xlabel("time after GPU idle->TDP step  [s]")
    ax.set_ylabel("PIC-center temperature rise  [K]")
    ax.set_title("Thermal transient: glass low-passes the GPU power step\n"
                 "the microring array sees a slow, small rise -> a static tuning bias suffices")
    ax.grid(ls=":", alpha=.5); ax.legend(fontsize=9)
    fig.tight_layout(); fig.savefig(P("fig_thermal_transient.png"), dpi=200)
    print("wrote fig_thermal_transient.png")
