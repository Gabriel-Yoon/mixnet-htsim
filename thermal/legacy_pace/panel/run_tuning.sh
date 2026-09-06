#!/bin/bash
# Thermo-optic tuning-efficiency study: local single-ring heater, glass vs silicon.
#   module load ansys/2025R2 ; bash run_tuning.sh
# Output: thermal_tuning.csv (matflag,pheat_W,tring_C,dT_ring_K,eff_KperW,ptune1_W,ptune_total_W)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-4}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

run_case () {  # tag  param...
  local tag="$1"; shift
  { for kv in "$@"; do echo "$kv"; done; echo "/INPUT,thermal_tuning_body,inp"; } > "_tune_${tag}.inp"
  echo "  [MAPDL] $tag"
  "$MAPDL" -b -j "tun_${tag}" -np "$NP" -smp -i "_tune_${tag}.inp" -o "_out_tune_${tag}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_tune_${tag}.out" 2>/dev/null \
    || echo "    !! error in $tag (see _out_tune_${tag}.out)"
}

: > thermal_tuning.csv
echo "matflag,pheat_W,tring_C,dT_ring_K,eff_KperW,ptune1_W,ptune_total_W" >> thermal_tuning.csv

TREF=105       # operating far-field temperature [C]  (~ die Tj, from the steady study)
HCP=70000      # cold-plate effective convection [W/m^2K]: Si microchannel HTC, CFD-derived
               # (Coenen et al., IEEE TCPMT 2026, "Benchmarking the Thermal Impact of 2.5D/3D
               # Co-Packaged Optics on Si Photonic Devices", HTC=7e4 W/m^2K, Fig.11)
# two heater powers per material to confirm linearity (efficiency is power-independent)
for MAT in 1 0; do
  for PH in 0.010 0.020; do          # 10 mW, 20 mW per ring
    run_case "m${MAT}_$(echo $PH|tr -d .)" \
      "MATFLAG=$MAT" "PHEAT_W=$PH" "T_REF=$TREF" "HCP=$HCP" "CSVOUT='thermal_tuning.csv'"
  done
done
echo "DONE -> thermal_tuning.csv"; command -v column >/dev/null && column -t -s, thermal_tuning.csv || cat thermal_tuning.csv
