#!/bin/bash
# Full 4x4 glass PANEL thermal (16 GPU tiles). Package-scale gradient + per-tile.
# RUN ON A CPU NODE (bigger model):
#   salloc -A <acct> -q inferno -N1 -n8 --mem=16G -t1:00:00
#   module load ansys/2025R2 ; NP=8 bash run_panel.sh
# Output: panel_plane_<mat>.csv (PIC top-view x,y,T) + panel_tiles_<mat>.csv (per-tile)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

NX=4           # 4x4 tiles = 16 GPUs
PGPU=700       # W per tile (H100-class); use 1000 for B200-class
FHOT=0.5       # hotspot fraction (central 1/9 area)
NDPT=6        # lateral elements per tile  (12 -> ~2.5 mm; raise for finer on a big node)
TCP_IN=55; TCP_RISE=20; HCP=100000

run_case () {  # tag matflag
  local tag="$1" mf="$2"
  { echo "MATFLAG=$mf"; echo "NX=$NX"; echo "P_GPU=$PGPU"; echo "FHOT=$FHOT"; echo "NDPT=$NDPT";
    echo "TCP_IN=$TCP_IN"; echo "TCP_RISE=$TCP_RISE"; echo "HCP=$HCP";
    echo "CSVPLANE='panel_plane_${tag}'"; echo "CSVTILE='panel_tiles_${tag}'";
    echo "/INPUT,thermal_panel_body,inp"; } > "_pan_${tag}.inp"
  echo "  [MAPDL] panel $tag (NX=$NX, NDPT=$NDPT)"
  "$MAPDL" -b -j "pan_${tag}" -np "$NP" -smp -i "_pan_${tag}.inp" -o "_out_pan_${tag}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_pan_${tag}.out" 2>/dev/null \
    || echo "    !! error in $tag (see _out_pan_${tag}.out)"
}

run_case glass 1
# run_case si 0        # uncomment for the silicon control (doubles runtime)
echo "DONE -> panel_plane_glass.csv / panel_tiles_glass.csv"
wc -l panel_plane_glass.csv panel_tiles_glass.csv 2>/dev/null
