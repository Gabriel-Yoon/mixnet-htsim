#!/bin/bash
# Stabilization scenario: PIC temperature vs a fluctuating GPU power (square wave
# idle 200W <-> TDP 700W) at several fluctuation periods. Shows the package low-passes
# fast GPU transients so a thermo-optic control loop can stabilize the microrings.
#   module load ansys/2025R2 ; NP=8 bash run_stab.sh    (CPU node preferred)
# Output: stab_p<period>.csv  (time_s, T_pic_C) for each period.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

PHI=700; PLO=200; PPIC=25; TCP=60
HCP=70000  # Si microchannel cold-plate HTC, CFD-derived (Coenen et al., IEEE TCPMT 2026,
           # "Benchmarking the Thermal Impact of 2.5D/3D Co-Packaged Optics on Si Photonic
           # Devices", HTC=7e4 W/m^2K conservative reference value from Fig.11)

run_case () {  # tag period ncyc
  local tag="$1" per="$2" ncyc="$3"
  local dt=$(awk -v p="$per" 'BEGIN{printf "%.4f", p/25.0}')
  { echo "MATFLAG=1"; echo "PGPU_HI=$PHI"; echo "PGPU_LO=$PLO"; echo "PPIC_W=$PPIC";
    echo "TCP_C=$TCP"; echo "HCP=$HCP"; echo "T_PER=$per"; echo "NCYC=$ncyc"; echo "DT_S=$dt";
    echo "CSVOUT='stab_${tag}'"; echo "/INPUT,thermal_stab_body,inp"; } > "_stab_${tag}.inp"
  echo "  [MAPDL] period=${per}s (ncyc=$ncyc, dt=$dt)"
  "$MAPDL" -b -j "stab_${tag}" -np "$NP" -smp -i "_stab_${tag}.inp" -o "_out_stab_${tag}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_stab_${tag}.out" 2>/dev/null \
    || echo "    !! error in $tag (see _out_stab_${tag}.out)"
}

# period sweep from 20 ms to 40 s to map the thermal transfer function (ripple vs period).
# fast periods use many cycles (cheap, short); slow ones few. tag,period[s],ncyc
run_case p0p02  0.02  40
run_case p0p05  0.05  40
run_case p0p1   0.1   30
run_case p0p2   0.2   25
run_case p0p5   0.5   20
run_case p2     2.0   10
run_case p10    10.0  6
run_case p40    40.0  4
echo "DONE -> stab_p*.csv (period sweep)"
wc -l stab_p*.csv 2>/dev/null
