#!/bin/bash
# HIGH-RESOLUTION 4x4 panel thermal for publication 3D figures. glass + silicon.
# RUN ON A CPU NODE:
#   salloc -A <acct> -q inferno -N1 -n8 --mem=16G -t1:00:00
#   module load ansys/2025R2 ; NP=8 bash run_panel_hq.sh
# Output: panel_plane_{glass,si}.csv (fine PIC-layer x,y,T) + panel_tiles_{glass,si}.csv
# NDPT high -> smooth 3D surface. Panel mesh is light (1 vertical elem/layer) so this is cheap.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

NX=4; PGPU=700; FHOT=0.5
NDPT="${NDPT:-32}"          # lateral elements per tile (32 -> ~0.95 mm; smooth). raise to 40+ if desired.
TCP_IN=55; TCP_RISE=20
HCP=70000  # Si microchannel cold-plate HTC, CFD-derived (Coenen et al., IEEE TCPMT 2026,
           # "Benchmarking the Thermal Impact of 2.5D/3D Co-Packaged Optics on Si Photonic
           # Devices", HTC=7e4 W/m^2K conservative reference value from Fig.11)

run_case () {  # tag matflag
  local tag="$1" mf="$2"
  { echo "MATFLAG=$mf"; echo "NX=$NX"; echo "P_GPU=$PGPU"; echo "FHOT=$FHOT"; echo "NDPT=$NDPT";
    echo "TCP_IN=$TCP_IN"; echo "TCP_RISE=$TCP_RISE"; echo "HCP=$HCP";
    echo "CSVPLANE='panel_plane_${tag}'"; echo "CSVTILE='panel_tiles_${tag}'";
    echo "/INPUT,thermal_panel_body,inp"; } > "_panhq_${tag}.inp"
  echo "  [MAPDL] panel-HQ $tag (NDPT=$NDPT)"
  "$MAPDL" -b -j "panhq_${tag}" -np "$NP" -smp -i "_panhq_${tag}.inp" -o "_out_panhq_${tag}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_panhq_${tag}.out" 2>/dev/null \
    || echo "    !! error in $tag (see _out_panhq_${tag}.out)"
}

run_case glass 1
run_case si    0
echo "DONE. plane/tile CSVs ready for plot_thermal_fig_3d.py and plot_thermal_fig_compact.py"
wc -l panel_plane_glass.csv panel_plane_si.csv 2>/dev/null
