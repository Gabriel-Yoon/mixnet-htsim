#!/bin/bash
# Follow-up cells on the validated map body, plus PIC-plane cuts for the figure.
#
#  1. tin40    -- same map, 40 C inlet. Tests the linearity claim directly rather
#                 than inferring it: at fixed h the problem is linear in coolant
#                 temperature, so a 15 C lower inlet should drop the outlet corner
#                 by ~15 C, to about 120. If it lands at 120 +/- 1 the sentence
#                 "a 40 C inlet or a 100k-class cold plate holds the 100-120 C
#                 ring band" is a result; otherwise it is not.
#  2. h100k    -- the design map at the archived cold plate, so the table has both
#                 axes at both values and die_only@100k connects to map@70k.
#  3. plane cuts at the PIC depth for the 70k glass and Si maps -- the field the
#                 regenerated figure shows, with the optics ON at the cited h,
#                 instead of the die-only 100k field it shows today.
#
# Output names are hardcoded; %PARAM% substitution is what failed before.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

OUT=panel_calplane_tiles.csv
echo "paper_ref,variant,substrate,pj_bit,hcp,tcp_in,tile_i,tile_j,tile_class,pic_w,pic_max_C,pic_min_C,pic_spread_C,die_max_C,bc_source" > "$OUT"

classof () { local i=$1 j=$2 n=0
  [ "$i" = 0 ] && n=$((n+1)); [ "$i" = 3 ] && n=$((n+1))
  [ "$j" = 0 ] && n=$((n+1)); [ "$j" = 3 ] && n=$((n+1))
  case $n in 0) echo interior;; 1) echo edge;; *) echo corner;; esac; }

run () {  # variant matflag pjbit hcp tcpin pic_int pic_edge pic_corner pic_tune planetag
  local v=$1 mf=$2 pj=$3 hcp=$4 tin=$5 pi=$6 pe=$7 pc=$8 pt=$9 plane=${10}
  local mat=glass; [ "$mf" = 0 ] && mat=si
  {
    echo "MATFLAG=$mf"; echo "NX=4"; echo "P_GPU=700"; echo "FHOT=0.5"; echo "NDPT=32"
    echo "TCP_IN=$tin"; echo "TCP_RISE=20"; echo "HCP=$hcp"
    echo "PIC_INT=$pi"; echo "PIC_EDGE=$pe"; echo "PIC_CORNER=$pc"; echo "PIC_TUNE=$pt"
    echo "/INPUT,thermal_panel_map_body,inp"
    echo "/POST1"
    echo "SET,LAST"
    echo "TILE_W=28.3e-3 \$ GAP=2.0e-3 \$ PT=TILE_W+GAP \$ NX=4"
    echo "T_BRD=0.5e-3 \$ T_SUB=0.7e-3 \$ T_PIC=0.05e-3"
    echo "Z1=T_BRD \$ Z2=Z1+T_SUB \$ Z3=Z2+T_PIC"
    if [ -n "$plane" ]; then
      echo "ZPIC=(Z2+Z3)/2 \$ TOLZ=T_PIC/2"
      echo "NSEL,S,LOC,Z,ZPIC-TOLZ,ZPIC+TOLZ"
      echo "*GET,NUMMAX,NODE,,NUM,MAX"
      echo "*DIM,XX,ARRAY,NUMMAX"
      echo "*DIM,YY,ARRAY,NUMMAX"
      echo "*DIM,TT,ARRAY,NUMMAX"
      echo "*DIM,SS,ARRAY,NUMMAX"
      echo "*VGET,XX(1),NODE,1,LOC,X"
      echo "*VGET,YY(1),NODE,1,LOC,Y"
      echo "*VGET,TT(1),NODE,1,TEMP"
      echo "*VGET,SS(1),NODE,1,NSEL"
      echo "*CFOPEN,panel_plane_${plane},csv"
      echo "*VMASK,SS(1)"
      echo "*VWRITE,XX(1),YY(1),TT(1)"
      echo "(E14.7,',',E14.7,',',F10.4)"
      echo "*CFCLOS"
      echo "ALLSEL"
    fi
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
  } > "_x_${v}.inp"

  echo "  [MAPDL] $v (mat=$mat hcp=$hcp Tin=$tin)"
  "$MAPDL" -b -j "x_${v}" -np "$NP" -smp -i "_x_${v}.inp" -o "_out_x_${v}.out" >/dev/null 2>&1
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_x_${v}.out" 2>/dev/null \
    || echo "    !! errors -- see _out_x_${v}.out"
  [ -s "_tiles_${v}.csv" ] || { echo "    !! no tile csv"; return; }
  while IFS=, read -r ti tj pmax pmin spread dmax; do
    ti=$(echo "$ti" | tr -d ' .'); tj=$(echo "$tj" | tr -d ' .'); [ -z "$ti" ] && continue
    local cls; cls=$(classof "$ti" "$tj")
    local w=$pi; [ "$cls" = edge ] && w=$pe; [ "$cls" = corner ] && w=$pc
    w=$(awk -v a="$w" -v b="$pt" 'BEGIN{printf "%.2f", a+b}')
    echo "thermal,$v,$mat,$pj,$hcp,$tin,$ti,$tj,$cls,$w,$(echo $pmax|tr -d ' '),$(echo $pmin|tr -d ' '),$(echo $spread|tr -d ' '),$(echo $dmax|tr -d ' '),wrapper:run_panel_extra.sh" >> "$OUT"
  done < "_tiles_${v}.csv"
  printf "    corner-inlet(0,0)=%s  outlet(3,3)=%s\n" \
    "$(head -1 _tiles_${v}.csv | cut -d, -f3 | tr -d ' ')" \
    "$(tail -1 _tiles_${v}.csv | cut -d, -f3 | tr -d ' ')"
  [ -n "$plane" ] && [ -s "panel_plane_${plane}.csv" ] && \
    echo "    plane: panel_plane_${plane}.csv  $(wc -l < panel_plane_${plane}.csv) lines"
}

echo "### PIC-plane cut at the CALIBRATED operating point (Fig 4) ###"
run cal_h200k_tin40_plane    1 1.15 200000 40 14.1 35.9 57.7 1.44 glass_cal_h200k_tin40
run cal_h200k_tin40_plane_si 0 1.15 200000 40 14.1 35.9 57.7 1.44 si_cal_h200k_tin40
echo "=== DONE ==="
column -s, -t "" | head -12
