#!/bin/bash
# Interface thermal resistance sweep, single tile, steady state.
#
# WHY. Every steady result so far merges the layer nodes, i.e. assumes PERFECT
# thermal contact between board, substrate, PIC, RDL and die. Real stacks have
# interface resistance, and the PIC sits under two of those interfaces, so its
# temperature -- and the resonance drift the paper claims from it -- is directly
# exposed. A perfect interface is an unstated optimism in our favour, and this
# says how much it is worth.
#
# R_int in {0.02, 0.05, 0.10} cm^2.K/W at die|RDL, RDL|PIC and PIC|substrate,
# plus a perfect-contact reference so the delta is attributable. h=200k, plate
# 60 C (40 C inlet + 20 K rise at the outlet tile), NDPT=16, GPU 700 W, FHOT=0.5
# -- identical to the step and schedule runs.
#
# TWO PIC POWERS, because "the design map at 1.15 pJ/bit" admits two readings and
# both are cheap here:
#   43 W  the 1600-provisioned corner power the other tile decks use
#   70 W  the full-provision figure at 1.15 pJ/bit from docs/energy_model.md
#         ("7.66 TB/s x 8 x 1.15 pJ/bit = 70.5 W")
# Reporting both means the answer does not depend on which was meant.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null
SRC=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/thermal/legacy_pace/panel
OUT=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/thermal/tile_rint.csv
cp "$SRC/thermal_tile_rint.inp" ./thermal_tile_rint.inp

echo "paper_ref,variant,substrate,hcp,tcp_C,p_gpu_W,p_pic_W,r_int_cm2KW,t_pic_C,delta_vs_perfect_K,status,note" > "$OUT"

run () { # variant p_pic r_int
  local v=$1 ppic=$2 rint=$3
  { echo "MATFLAG=1"; echo "HCP=200000"; echo "TCP=60"; echo "P_GPU=700"
    echo "P_PIC=$ppic"; echo "FHOT=0.5"; echo "NDPT=16"; echo "R_INT_CM2KW=$rint"
    echo "/INPUT,thermal_tile_rint,inp"
    echo "/POST1"
    echo "SET,LAST"
    echo "/OUTPUT,tile_rint_${v},csv"
    echo "*GET,TPIC,NODE,NMON,TEMP"
    echo "*VWRITE,TPIC"
    echo "(F12.4)"
    echo "/OUTPUT"
    echo "FINISH"
  } > "_ri_${v}.inp"
  echo "  [MAPDL] $v (P_PIC=$ppic R_int=$rint cm2K/W)"
  "$MAPDL" -b -j "ri_${v}" -np "$NP" -smp -i "_ri_${v}.inp" -o "_out_ri_${v}.out" >/dev/null 2>&1
  local status=final
  grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_ri_${v}.out" 2>/dev/null \
    || { status=solve_errors; echo "    !! errors -- see _out_ri_${v}.out"; }
  local t
  t=$(grep -oE "^ *[0-9]+\.[0-9]+" "tile_rint_${v}.csv" 2>/dev/null | head -1 | tr -d ' ')
  if [ -z "$t" ]; then echo "    !! no temperature extracted"; return; fi
  echo "$v $ppic $rint $t $status" >> ./_rint_rows.txt
  printf "    PIC centre: %s C\n" "$t"
}

rm -f ./_rint_rows.txt
for ppic in 43 70; do
  echo "########## P_PIC = ${ppic} W ##########"
  run perfect_p${ppic} "$ppic" 1e-9      # perfect-contact reference
  for r in 0.02 0.05 0.10; do
    run r${r}_p${ppic} "$ppic" "$r"
  done
done

# deltas against the perfect-contact reference at the same PIC power
python3 - "$OUT" <<'PY'
import sys, collections
out = sys.argv[1]
rows = []
for L in open("./_rint_rows.txt"):
    v, ppic, rint, t, status = L.split()
    rows.append((v, float(ppic), float(rint), float(t), status))
base = {p: t for v, p, r, t, s in rows if r <= 1e-8 for _ in [0]}
base = {}
for v, p, r, t, s in rows:
    if r <= 1e-8:
        base[p] = t
with open(out, "a") as fh:
    for v, p, r, t, s in sorted(rows, key=lambda x: (x[1], x[2])):
        d = t - base.get(p, t)
        fh.write(f"thermal,{v},glass,200000,60,700,{p:.0f},{r:g},{t:.3f},{d:+.3f},{s},"
                 f"\"interface resistance at die|RDL, RDL|PIC, PIC|substrate as a thin layer of "
                 f"k=t/R; r_int 1e-9 is the perfect-contact reference every delta is taken "
                 f"against; P_PIC 43 W is the 1600-provisioned corner, 70 W the 1.15 pJ/bit "
                 f"full-provision figure from docs/energy_model.md\"\n")
        print(f"  P_PIC={p:.0f}W R_int={r:g} -> PIC {t:.3f} C  ({d:+.3f} K vs perfect contact)")
PY
echo "=== DONE ==="
column -s, -t "$OUT" | cut -c1-150
