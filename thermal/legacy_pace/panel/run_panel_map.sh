#!/bin/bash
# Panel thermal with per-tile PIC self-heating: gate first, then the design map.
#
# GATE (variant=die_only): all PIC powers zero must reproduce the die-only solve
# exactly -- 119.300 C PIC max for glass. If it does not, the new body differs
# from thermal_panel_body.inp somewhere other than the PIC source and nothing
# below counts.
#
# Every output filename is hardcoded by this wrapper. The original deck's
# *CFOPEN,%CSVPLANE%,csv silently wrote to a file named with the literal token,
# which is why four expected CSVs never existed -- see docs/methods_provenance.md
# sub-class C. Table parameters (%TCPTAB% in SFA) are a different mechanism and
# are kept.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

OUT=panel_map_tiles.csv
echo "paper_ref,variant,substrate,pj_bit,hcp,tile_i,tile_j,tile_class,pic_w,pic_max_C,pic_min_C,pic_spread_C,die_max_C" > "$OUT"

# tile classes for a 4x4: corners have two panel edges, edges one, interior none
classof () { local i=$1 j=$2 n=0
  [ "$i" = 0 ] && n=$((n+1)); [ "$i" = 3 ] && n=$((n+1))
  [ "$j" = 0 ] && n=$((n+1)); [ "$j" = 3 ] && n=$((n+1))
  case $n in 0) echo interior;; 1) echo edge;; *) echo corner;; esac; }

run () {  # variant matflag pjbit hcp pic_int pic_edge pic_corner pic_tune
  local v=$1 mf=$2 pj=$3 hcp=$4 pi=$5 pe=$6 pc=$7 pt=$8
  local mat=glass; [ "$mf" = 0 ] && mat=si
  { echo "MATFLAG=$mf"; echo "NX=4"; echo "P_GPU=700"; echo "FHOT=0.5"; echo "NDPT=32"
    echo "TCP_IN=55"; echo "TCP_RISE=20"; echo "HCP=$hcp"
    echo "PIC_INT=$pi"; echo "PIC_EDGE=$pe"; echo "PIC_CORNER=$pc"; echo "PIC_TUNE=$pt"
    echo "/INPUT,thermal_panel_map_body,inp"
    echo "/POST1"
    echo "SET,LAST"
    echo "TILE_W=28.3e-3 \$ GAP=2.0e-3 \$ PT=TILE_W+GAP"
    echo "*CFOPEN,_tiles_${v},csv"
    echo "*DO,TI,0,3"
    echo "  *DO,TJ,0,3"
    echo "    X0=TI*PT \$ X1=X0+TILE_W \$ Y0=TJ*PT \$ Y1=Y0+TILE_W"
    echo "    ESEL,S,MAT,,3 \$ ESEL,R,CENT,X,X0,X1 \$ ESEL,R,CENT,Y,Y0,Y1 \$ NSLE,S \$ NSORT,TEMP"
    echo "    *GET,PMAX,SORT,,MAX \$ *GET,PMIN,SORT,,MIN"
    echo "    ALLSEL"
    echo "    ESEL,S,MAT,,5 \$ ESEL,R,CENT,X,X0,X1 \$ ESEL,R,CENT,Y,Y0,Y1 \$ NSLE,S \$ NSORT,TEMP"
    echo "    *GET,DMAX,SORT,,MAX"
    echo "    ALLSEL"
    echo "    *VWRITE,TI,TJ,PMAX,PMIN,PMAX-PMIN,DMAX"
    echo "(F4.0,',',F4.0,',',F10.3,',',F10.3,',',F10.3,',',F10.3)"
    echo "  *ENDDO"
    echo "*ENDDO"
    echo "*CFCLOS"
    echo "FINISH"
  } > "_map_${v}.inp"

  echo "  [MAPDL] $v  (mat=$mat, hcp=$hcp, PIC int/edge/corner = $pi/$pe/$pc +$pt)"
  "$MAPDL" -b -j "map_${v}" -np "$NP" -smp -i "_map_${v}.inp" -o "_out_map_${v}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_map_${v}.out" 2>/dev/null \
    || echo "    !! errors -- see _out_map_${v}.out"
  if [ ! -s "_tiles_${v}.csv" ]; then echo "    !! _tiles_${v}.csv missing"; return; fi

  while IFS=, read -r ti tj pmax pmin spread dmax; do
    ti=$(echo "$ti" | tr -d ' .'); tj=$(echo "$tj" | tr -d ' .')
    [ -z "$ti" ] && continue
    local cls; cls=$(classof "$ti" "$tj")
    local w=$pi; [ "$cls" = edge ] && w=$pe; [ "$cls" = corner ] && w=$pc
    w=$(awk -v a="$w" -v b="$pt" 'BEGIN{printf "%.2f", a+b}')
    echo "thermal,$v,$mat,$pj,$hcp,$ti,$tj,$cls,$w,$(echo $pmax|tr -d ' '),$(echo $pmin|tr -d ' '),$(echo $spread|tr -d ' '),$(echo $dmax|tr -d ' ')" >> "$OUT"
  done < "_tiles_${v}.csv"
  printf "    tile(0,0) PIC max = %s   tile(3,3) = %s\n" \
    "$(head -1 _tiles_${v}.csv | cut -d, -f3 | tr -d ' ')" \
    "$(tail -1 _tiles_${v}.csv | cut -d, -f3 | tr -d ' ')"
}

echo "########## GATE: die_only must reproduce 119.300 C (glass) ##########"
run die_only 1 none 100000 0 0 0 0
G=$(awk -F, '$2=="die_only"{if($10+0>m)m=$10+0}END{printf "%.3f", m}' "$OUT")
echo "  die_only PIC max = $G   (expect 119.300)"
if [ "$G" != "119.300" ]; then
  echo "  !! GATE FAILED -- the map body differs from thermal_panel_body.inp beyond the PIC source."
  echo "  !! Stopping; design-map rows would not be comparable to the committed die-only solve."
  exit 1
fi
echo "  GATE PASSED"

echo "########## design map at 384/3200, 1.15 pJ/bit ##########"
run design_map_1p15 1 1.15 70000 14.1 35.9 57.7 1.44
echo "########## design map at the 2.62 pJ/bit bracket ##########"
run design_map_2p62 1 2.62 70000 32.1 81.9 131.6 1.44
echo "########## cold-plate sensitivity at the 1.15 map ##########"
run hcp_50k 1 1.15 50000 14.1 35.9 57.7 1.44
run hcp_30k 1 1.15 30000 14.1 35.9 57.7 1.44
echo "########## silicon control at the 1.15 map ##########"
run design_map_1p15_si 0 1.15 70000 14.1 35.9 57.7 1.44

echo "=== DONE ==="; column -s, -t "$OUT" | head -40
