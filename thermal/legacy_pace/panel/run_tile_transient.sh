#!/bin/bash
# PIC thermal transient on THIS stack (glass panel), single outlet tile.
# Replaces the ICCAD OIO3D single-stack numbers, which are a different stack.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

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
  python3 - "$v" <<'PY'
import sys,re
v=sys.argv[1]
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
print(f"    base={T0:.3f} C  peak={Tmax:.3f} C  dT={dT:.3f} K  "
      f"t10={t10}  t90={t90}  rise_10_90={'%.6g'%(t90-t10) if t10 is not None and t90 is not None else 'n/a'} s  "
      f"({len(pts)} pts)")
PY
}

echo "### PIC transient, outlet tile, calibrated cold plate (die in spec) ###"
run glass_stack_h200k 1 200000 60 43 16 0.05
echo "### same at the cited single-phase microchannel h, for comparison ###"
run glass_stack_h70k  1  70000 60 43 16 0.05
echo "=== DONE ==="
