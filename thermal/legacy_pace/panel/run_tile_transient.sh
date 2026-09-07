#!/bin/bash
# PIC thermal transient on THIS stack (glass panel), single outlet tile.
# Replaces the ICCAD OIO3D single-stack numbers, which are a different stack.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null
# This script printed its results and never wrote the CSV that
# experiments/results/thermal/tile_transient.csv claims to hold them -- an
# artifact with no producer (methods_provenance sub-class B). It writes it now.
OUTCSV=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/thermal/tile_transient.csv
echo "paper_ref,variant,substrate,hcp,tcp_C,p_pic_W,p_gpu_W,tend_s,base_C,peak_C,delta_T_K,rise_10_90_s,tend_over_rise,n_points,status,note" > "$OUTCSV"

run () { # variant matflag hcp tcp p_pic ndpt tend
  local v=$1 mf=$2 hcp=$3 tcp=$4 ppic=$5 ndpt=$6 tend=$7
  { echo "MATFLAG=$mf"; echo "HCP=$hcp"; echo "TCP=$tcp"; echo "P_GPU=700"
    echo "FHOT=0.5"; echo "P_PIC=$ppic"; echo "NDPT=$ndpt"; echo "TEND=$tend"
    echo "/INPUT,thermal_tile_transient,inp"
    echo "/POST26"
    echo "NUMVAR,200"
    echo "NSOL,2,NMON,TEMP"
    echo "/OUTPUT,tile_transient_${v},csv"
    echo "PRVAR,2"
    echo "/OUTPUT"
    echo "FINISH"
  } > "_tr_${v}.inp"
  echo "  [MAPDL] $v (h=$hcp Tcp=$tcp P_PIC=$ppic)"
  "$MAPDL" -b -j "tr_${v}" -np "$NP" -smp -i "_tr_${v}.inp" -o "_out_tr_${v}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_tr_${v}.out" 2>/dev/null \
    || echo "    !! errors -- see _out_tr_${v}.out"
  python3 - "$v" "$hcp" "$tcp" "$ppic" "$tend" "$OUTCSV" <<'PY'
import sys,re
v=sys.argv[1]; hcp=sys.argv[2]; tcp=sys.argv[3]; ppic=sys.argv[4]
tend=float(sys.argv[5]); outcsv=sys.argv[6]
try: lines=open(f"tile_transient_{v}.csv",errors="ignore").read().splitlines()
except OSError: print("    !! no csv"); raise SystemExit
pts=[]
for L in lines:
    m=re.match(r"\s*([0-9.eE+-]+)\s+([0-9.eE+-]+)\s*$",L)
    if m:
        try: pts.append((float(m.group(1)),float(m.group(2))))
        except ValueError: pass
if len(pts)<3: print(f"    !! only {len(pts)} points"); raise SystemExit
t0,T0=pts[0]; Tmax=max(p[1] for p in pts); dT=Tmax-T0
tgt10,tgt90=T0+0.1*dT,T0+0.9*dT
t10=t90=None
for t,T in pts:
    if t10 is None and T>=tgt10: t10=t
    if t90 is None and T>=tgt90: t90=t; break
rise = (t90 - t10) if (t10 is not None and t90 is not None) else None
print(f"    base={T0:.3f} C  peak={Tmax:.3f} C  dT={dT:.3f} K  "
      f"t10={t10}  t90={t90}  rise_10_90={'%.6g'%rise if rise else 'n/a'} s  "
      f"({len(pts)} pts)")
# tend/rise is the convergence gate: a transient quoted as a steady value needs an
# end time several times its own measured response. Below 5 the row says so
# instead of presenting a truncated integration as an asymptote.
ratio = (tend / rise) if rise else 0.0
status = "final" if ratio >= 5 else "truncated_integration"
with open(outcsv, "a") as fh:
    fh.write(f"thermal,{v},glass,{hcp},{tcp},{ppic},700,{tend:g},{T0:.3f},{Tmax:.3f},{dT:.3f},"
             f"{'%.6g'%rise if rise else ''},{ratio:.2f},{len(pts)},{status},"
             f"\"idle->TDP step; tend_over_rise is TEND in units of this run's own measured "
             f"10-90 rise -- below 5 the peak is NOT the asymptote (the original TEND=0.05 s runs "
             f"sat at ~1.1-1.5 and understated the rise by 10% at h=200k and 39% at h=70k)\"\n")
PY
}

echo "### PIC transient, outlet tile, calibrated cold plate (die in spec) ###"
run glass_stack_h200k 1 200000 60 43 16 0.05
# TEND=0.05 s is only ~1.5 rise-times (10-90 is 33 ms), so the peak this reports
# is NOT the steady value: a direct steady solve at identical BCs gives 89.572 C
# against this run's 86.790 C peak, so the published 26.159 K rise understates
# the steady rise by ~10%. Re-run to 0.30 s (~9 rise-times) to measure the
# asymptote instead of assuming the shorter run had reached it.
run glass_stack_h200k_long 1 200000 60 43 16 0.30
echo "### same at the cited single-phase microchannel h, for comparison ###"
run glass_stack_h70k  1  70000 60 43 16 0.05
# Same reason as the h200k long run: at 70k the response is SLOWER (37 ms
# 10-90), so TEND=0.05 s is even further from the asymptote and the published
# 43.830 K is a lower bound rather than a measurement.
run glass_stack_h70k_long  1  70000 60 43 16 0.30
echo "=== DONE ==="
