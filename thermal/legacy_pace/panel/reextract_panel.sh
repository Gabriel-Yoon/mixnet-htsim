#!/bin/bash
# Re-extract the 4x4 panel results from the EXISTING .rth files. No re-solve.
#
# WHY THIS IS NEEDED. thermal_panel_body.inp ends with *CFOPEN,%CSVPLANE%,csv and
# *CFOPEN,%CSVTILE%,csv. The substitution never happened: the directory contains
# files literally named "%CSVPLANE%.csv" and "%CSVTILE%.csv", and none of the four
# expected panel_{plane,tiles}_{glass,si}.csv exist. The solves themselves are
# fine -- panhq_glass.rth and panhq_si.rth, 49 MB each, distinct md5s, so glass
# and the silicon control are both real.
#
# THE FIX IS NOT TO DIAGNOSE MAPDL'S SUBSTITUTION RULES. It is to stop depending
# on them: every output filename below is hardcoded, one deck generated per case
# by the shell. That is also why this re-extraction can be trusted where the
# original could not -- there is no parameter left to fail to expand.
#
# Geometry constants are re-declared rather than assumed to survive RESUME, and
# they are copied verbatim from thermal_panel_body.inp so the tile windows match
# the ones the solve used.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null

extract () {   # jobname  outtag
  local job="$1"
  local tag="$2"
  local deck="_reextract_${tag}.inp"
  cat > "$deck" <<EOF
! Re-extraction of ${job}.rth -- hardcoded output names (see reextract_panel.sh).
/CLEAR,NOSTART
RESUME,${job},db
/POST1
FILE,${job},rth
SET,LAST

! geometry, verbatim from thermal_panel_body.inp
NX=4
TILE_W=28.3e-3 \$ GAP=2.0e-3 \$ PT=TILE_W+GAP
PANEL=NX*PT
T_BRD=0.5e-3 \$ T_SUB=0.7e-3 \$ T_PIC=0.05e-3 \$ T_RDL=0.1e-3 \$ T_DIE=0.75e-3
Z0=0 \$ Z1=Z0+T_BRD \$ Z2=Z1+T_SUB \$ Z3=Z2+T_PIC \$ Z4=Z3+T_RDL \$ Z5=Z4+T_DIE

! ---- PIC-layer top-view plane (X,Y,TEMP) ----
ZPIC=(Z2+Z3)/2 \$ TOLZ=T_PIC/2
NSEL,S,LOC,Z,ZPIC-TOLZ,ZPIC+TOLZ
*GET,NUMMAX,NODE,,NUM,MAX
*DIM,XX,ARRAY,NUMMAX
*DIM,YY,ARRAY,NUMMAX
*DIM,TT,ARRAY,NUMMAX
*DIM,SS,ARRAY,NUMMAX
*VGET,XX(1),NODE,1,LOC,X
*VGET,YY(1),NODE,1,LOC,Y
*VGET,TT(1),NODE,1,TEMP
*VGET,SS(1),NODE,1,NSEL
*CFOPEN,panel_plane_${tag},csv
*VMASK,SS(1)
*VWRITE,XX(1),YY(1),TT(1)
(E14.7,',',E14.7,',',F10.4)
*CFCLOS
ALLSEL

! ---- per-tile: PIC peak/min/spread + die peak ----
*CFOPEN,panel_tiles_${tag},csv
*DO,TI,0,NX-1
  *DO,TJ,0,NX-1
    X0=TI*PT \$ X1=X0+TILE_W \$ Y0=TJ*PT \$ Y1=Y0+TILE_W
    ESEL,S,MAT,,3 \$ ESEL,R,CENT,X,X0,X1 \$ ESEL,R,CENT,Y,Y0,Y1 \$ NSLE,S \$ NSORT,TEMP
    *GET,PMAX,SORT,,MAX \$ *GET,PMIN,SORT,,MIN
    ALLSEL
    ESEL,S,MAT,,5 \$ ESEL,R,CENT,X,X0,X1 \$ ESEL,R,CENT,Y,Y0,Y1 \$ NSLE,S \$ NSORT,TEMP
    *GET,DMAX,SORT,,MAX
    ALLSEL
    *VWRITE,TI,TJ,PMAX,PMIN,PMAX-PMIN,DMAX
(F4.0,',',F4.0,',',F10.3,',',F10.3,',',F10.3,',',F10.3)
  *ENDDO
*ENDDO
*CFCLOS

! ---- whole-panel extremes, for the section's headline numbers ----
ESEL,S,MAT,,3 \$ NSLE,S \$ NSORT,TEMP
*GET,PICMAX,SORT,,MAX \$ *GET,PICMIN,SORT,,MIN
ALLSEL
ESEL,S,MAT,,5 \$ NSLE,S \$ NSORT,TEMP
*GET,DIEMAX,SORT,,MAX \$ *GET,DIEMIN,SORT,,MIN
ALLSEL
*CFOPEN,panel_summary_${tag},csv
*VWRITE,PICMAX,PICMIN,PICMAX-PICMIN,DIEMAX,DIEMIN
('pic_max,pic_min,pic_spread,die_max,die_min')
*VWRITE,PICMAX,PICMIN,PICMAX-PICMIN,DIEMAX,DIEMIN
(F10.3,',',F10.3,',',F10.3,',',F10.3,',',F10.3)
*CFCLOS
FINISH
EOF
  echo "  [MAPDL] re-extracting ${job} -> panel_{plane,tiles,summary}_${tag}.csv"
  "$MAPDL" -b -j "reext_${tag}" -np "$NP" -smp -i "$deck" -o "_out_reext_${tag}.out" >/dev/null 2>&1
  if grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_reext_${tag}.out" 2>/dev/null; then
    echo "    solve-file read OK"
  else
    echo "    !! errors -- see _out_reext_${tag}.out"
  fi
  for f in panel_plane_${tag}.csv panel_tiles_${tag}.csv panel_summary_${tag}.csv; do
    if [ -s "$f" ]; then printf "    %-28s %s lines\n" "$f" "$(wc -l < "$f")"
    else echo "    !! $f MISSING or empty"; fi
  done
}

extract panhq_glass glass
extract panhq_si    si

echo
echo "=== per-tile, glass ==="; cat panel_tiles_glass.csv 2>/dev/null
echo "=== summary ==="; cat panel_summary_glass.csv panel_summary_si.csv 2>/dev/null
echo
echo "=== FINGERPRINT vs the surviving literal file (tile 0,0 = 94.010 / 1,0 = 99.005) ==="
head -2 "%CSVTILE%.csv" 2>/dev/null
echo "  if neither re-extraction matches, the published figure came from a THIRD run"
echo "  (likely _run_panel_small.sh at HCP=100000, NDPT=6)."
