#!/bin/bash
# Scheduled (periodic) PIC transient on the glass panel stack, single outlet tile.
#
# The idle->TDP step already measured gives the OUTER bound (33-37 ms 10-90 rise,
# 26-44 K). This asks the question the paper actually needs: what does the PIC
# swing by when the GPU alternates between compute and communication at the rate
# our own runs measure?
#
# Periods are taken from measured rows of this paper:
#   86.75 ms  one EP=16 iteration (the glass EP=16 cliff row, relay=0, 0 RTO)
#   10.84 ms  one microbatch      (that iteration / mb=8)
# The stack's 33-37 ms response sits between them, so the two are genuinely
# different regimes rather than two points on a flat line.
#
# 50% duty, 700 W high / 210 W low. The 210 is an ASSUMPTION -- 30% of TDP as the
# communication-phase floor, because a GPU waiting on an all-to-all is not at
# 0 W -- and is recorded in the CSV as such. PIC held at 43 W throughout.
# h=200k, plate 60 C (= 40 C inlet + 20 K rise at the outlet tile), same BCs and
# mesh (NDPT=16) as the step run.
#
# Reported: peak-to-trough over the LAST period, once the periodic steady state
# is reached; NPER=6 so five periods precede it.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null
DECK=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/thermal/legacy_pace/panel/thermal_tile_schedule.inp
OUT=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/thermal/tile_schedule.csv
cp "$DECK" ./thermal_tile_schedule.inp

echo "paper_ref,variant,substrate,hcp,tcp_C,p_pic_W,p_hi_W,p_lo_W,duty,period_s,n_periods,t_min_C,t_max_C,delta_pp_K,n_points_last_period,status,note" > "$OUT"

run () { # variant period nper p_hi p_lo
  local v=$1 period=$2 nper=$3 phi=$4 plo=$5
  { echo "MATFLAG=1"; echo "HCP=200000"; echo "TCP=60"; echo "P_PIC=43"
    echo "P_HI=$phi"; echo "P_LO=$plo"; echo "FHOT=0.5"; echo "NDPT=16"
    echo "PERIOD=$period"; echo "NPER=$nper"
    echo "/INPUT,thermal_tile_schedule,inp"
    echo "/POST26"
    echo "NUMVAR,200"
    echo "NSOL,2,NMON,TEMP"
    echo "/OUTPUT,tile_schedule_${v},csv"
    echo "PRVAR,2"
    echo "/OUTPUT"
    echo "FINISH"
  } > "_sch_${v}.inp"
  echo "  [MAPDL] $v (period=${period}s nper=$nper P_hi=$phi P_lo=$plo)"
  "$MAPDL" -b -j "sch_${v}" -np "$NP" -smp -i "_sch_${v}.inp" -o "_out_sch_${v}.out" >/dev/null 2>&1
  local errs status
  errs=$(grep -c "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_sch_${v}.out" 2>/dev/null || echo 0)
  status=final; [ "$errs" = "0" ] && { status=solve_errors; echo "    !! errors -- see _out_sch_${v}.out"; }

  python3 - "$v" "$period" "$nper" "$phi" "$plo" "$status" "$OUT" <<'PY'
import sys, re
v, period, nper, phi, plo, status, out = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7]
try:
    lines = open(f"tile_schedule_{v}.csv", errors="ignore").read().splitlines()
except OSError:
    print("    !! no csv"); raise SystemExit
pts = []
for L in lines:
    m = re.match(r"\s*([0-9.eE+-]+)\s+([0-9.eE+-]+)\s*$", L)
    if m:
        try: pts.append((float(m.group(1)), float(m.group(2))))
        except ValueError: pass
if len(pts) < 5:
    print(f"    !! only {len(pts)} points"); raise SystemExit
# the LAST period only: the periodic steady state, not the warm-up
t0 = (nper - 1) * period
last = [T for t, T in pts if t >= t0 - 1e-12]
if len(last) < 3:
    print(f"    !! only {len(last)} points in the last period -- time step too coarse")
    raise SystemExit
lo, hi = min(last), max(last)
print(f"    last period: {lo:.3f} -> {hi:.3f} C, peak-to-trough {hi-lo:.3f} K over {len(last)} points")
with open(out, "a") as fh:
    fh.write(f"thermal,{v},glass,200000,60,43,{phi},{plo},0.5,{period},{nper},"
             f"{lo:.3f},{hi:.3f},{hi-lo:.3f},{len(last)},{status},"
             f"\"periodic 50% duty; P_lo is an ASSUMPTION (30% of TDP as the communication-phase "
             f"floor, not measured); periods from this paper's own EP=16 row (86.75 ms iteration, "
             f"/8 microbatch); PIC constant at 43 W; peak-to-trough over the last period\"\n")
PY
}

# P_LO is the one assumption in this deck: the communication-phase floor is not
# measured. Bracketing it at 0 / 30% / 50% of TDP stops it being load-bearing --
# 0 W is the pessimistic extreme (and reduces to the step's own duty), 350 W the
# optimistic one. Each run is ~45 s, so the bracket costs less than arguing about
# the midpoint.
echo "########## iteration period (86.75 ms), P_LO bracket ##########"
run iter_86p75ms_lo0   0.08675 6 700   0
run iter_86p75ms       0.08675 6 700 210
run iter_86p75ms_lo350 0.08675 6 700 350
echo "########## microbatch period (10.84 ms), P_LO bracket ##########"
run mb_10p84ms_lo0     0.01084 6 700   0
run mb_10p84ms         0.01084 6 700 210
run mb_10p84ms_lo350   0.01084 6 700 350
echo "=== DONE ==="
column -s, -t "$OUT" 2>/dev/null | cut -c1-190
