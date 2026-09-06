#!/bin/bash
# Export the ring-heater temperature plane for glass and silicon -> heatmaps.
#   module load ansys/2025R2 ; bash run_heatmap.sh
# Output: heatmap_glass.csv / heatmap_si.csv  (columns: x_m, z_m, temp_C)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-4}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

run_case () {  # tag matflag heatcsv
  local tag="$1" mf="$2" out="$3"
  # HCP=70000: Si microchannel cold-plate HTC, CFD-derived (Coenen et al., IEEE TCPMT 2026,
  # "Benchmarking the Thermal Impact of 2.5D/3D Co-Packaged Optics on Si Photonic Devices")
  { echo "MATFLAG=$mf"; echo "PHEAT_W=0.020"; echo "T_REF=105"; echo "HCP=70000";
    echo "HEATCSV='$out'"; echo "/INPUT,thermal_heatmap_body,inp"; } > "_hm_${tag}.inp"
  echo "  [MAPDL] $tag"
  "$MAPDL" -b -j "hm_${tag}" -np "$NP" -smp -i "_hm_${tag}.inp" -o "_out_hm_${tag}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_hm_${tag}.out" 2>/dev/null \
    || echo "    !! error in $tag (see _out_hm_${tag}.out)"
}

run_case glass 1 heatmap_glass
run_case si    0 heatmap_si
echo "DONE -> heatmap_glass.csv / heatmap_si.csv"
wc -l heatmap_glass.csv heatmap_si.csv 2>/dev/null
