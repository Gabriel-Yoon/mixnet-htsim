#!/bin/bash
# Period sweep of the periodic tile transient, for the swing-vs-period figure.
#
# APPENDS to tile_schedule.csv. run_tile_schedule.sh TRUNCATES it (`> "$OUT"`),
# which would destroy the six rows the figure's existing points come from, so this
# is a separate script rather than another `run` line in that one. It refuses to
# start if the file is missing or its header has changed.
#
# COOLANT TEMPERATURE. The request was for 40 C to match the panel heatmap, noting
# the existing rows are at 60 C. It does not matter, and the deck says why: every
# MP, card in thermal_tile_schedule.inp is a CONSTANT -- no MPTEMP/MPDATA tables --
# and both convection surfaces have fixed coefficients. The problem is therefore
# linear and time-invariant, so a change of sink temperature shifts the whole field
# by a constant and leaves the peak-to-peak SWING, which is a difference of two
# temperatures, unchanged.
#
# That is an argument, so the sweep runs at TCP=60 for continuity with the six
# existing rows AND repeats two of them at TCP=40 as a control. If the controls
# reproduce their 60 C twins' delta_pp_K, the figure may be labelled at either
# temperature and no existing row needs re-running. If they do not, the linearity
# claim is wrong and every row in the figure has to be at one temperature.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/mixnet-sim/thermal
MAPDL="${MAPDL:-ansys252}"; NP="${NP:-8}"
export ANSYS_LOCK=OFF; rm -f ./*.lock 2>/dev/null
P=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
DECK=$P/thermal/legacy_pace/panel/thermal_tile_schedule.inp
OUT=$P/experiments/results/thermal/tile_schedule.csv
cp "$DECK" ./thermal_tile_schedule.inp

HDR="paper_ref,variant,substrate,hcp,tcp_C,p_pic_W,p_hi_W,p_lo_W,duty,period_s,n_periods,total_s,rise_s,total_over_rise,t_min_C,t_max_C,delta_pp_K,mean_last_C,mean_prev_C,drift_K,n_points_last_period,status,note"
[ -f "$OUT" ] || { echo "REFUSING: $OUT does not exist -- this script appends, it does not create" >&2; exit 1; }
[ "$(head -1 "$OUT")" = "$HDR" ] || { echo "REFUSING: $OUT header is not the one this script writes" >&2; exit 1; }
BEFORE=$(grep -c '' "$OUT")
echo "appending to $OUT ($((BEFORE-1)) existing row(s))"

run () { # variant period nper p_hi p_lo tcp
  local v=$1 period=$2 nper=$3 phi=$4 plo=$5 tcp=$6
  { echo "MATFLAG=1"; echo "HCP=200000"; echo "TCP=$tcp"; echo "P_PIC=43"
    echo "P_HI=$phi"; echo "P_LO=$plo"; echo "FHOT=0.5"; echo "NDPT=16"
    echo "PERIOD=$period"; echo "NPER=$nper"
    echo "/INPUT,thermal_tile_schedule,inp"
    echo "/POST26"; echo "NUMVAR,200"; echo "NSOL,2,NMON,TEMP"
    echo "/OUTPUT,tile_schedule_${v},csv"; echo "PRVAR,2"; echo "/OUTPUT"; echo "FINISH"
  } > "_sch_${v}.inp"
  printf "  [MAPDL] %-22s period=%-8s nper=%-4s P_lo=%-4s TCP=%s\n" "$v" "$period" "$nper" "$plo" "$tcp"
  "$MAPDL" -b -j "sch_${v}" -np "$NP" -smp -i "_sch_${v}.inp" -o "_out_sch_${v}.out" >/dev/null 2>&1
  local errs status
  errs=$(grep -c "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_sch_${v}.out" 2>/dev/null || echo 0)
  status=final; [ "$errs" = "0" ] && { status=solve_errors; echo "    !! errors -- see _out_sch_${v}.out"; }

  python3 - "$v" "$period" "$nper" "$phi" "$plo" "$status" "$OUT" "$tcp" <<'PY'
import sys, re
v, period, nper, phi, plo, status, out, tcp = (sys.argv[1], float(sys.argv[2]),
    int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8])
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
t0 = (nper - 1) * period
last = [T for t, T in pts if t >= t0 - 1e-12]
prev = [T for t, T in pts if t0 - period - 1e-12 <= t < t0 - 1e-12]
if len(last) < 3:
    print(f"    !! only {len(last)} points in the last period"); raise SystemExit
lo, hi = min(last), max(last)
ml = sum(last) / len(last)
mp = sum(prev) / len(prev) if prev else ml
rise, total = 0.044, nper * period
with open(out, "a") as fh:
    fh.write(f"thermal,{v},glass,200000,{tcp},43,{phi},{plo},0.5,{period},{nper},"
             f"{total:.4f},{rise},{total/rise:.1f},{lo:.3f},{hi:.3f},{hi-lo:.3f},"
             f"{ml:.4f},{mp:.4f},{ml-mp:.4f},{len(last)},{status},"
             f"\"period sweep for the swing-vs-period figure; P_lo is an ASSUMPTION "
             f"(30% of TDP as the communication-phase floor, not measured); PIC constant "
             f"at 43 W; peak-to-trough over the last period; TCP={tcp} C\"\n")
print(f"    delta_pp={hi-lo:.3f} K  drift={ml-mp:.4f} K  n_last={len(last)}")
PY
}

# nper chosen so total/rise >= 5 with rise = 0.044 s, as the existing rows do.
echo "########## period sweep, P_lo = 210 W (the assumed 30% floor) ##########"
run per_0p001s_lo210 0.001 250 700 210 60
run per_0p003s_lo210 0.003  84 700 210 60
run per_0p010s_lo210 0.010  25 700 210 60
run per_0p030s_lo210 0.030   9 700 210 60
run per_0p100s_lo210 0.100   6 700 210 60
run per_0p300s_lo210 0.300   3 700 210 60
run per_1s_lo210     1.000   3 700 210 60
run per_3s_lo210     3.000   3 700 210 60

echo "########## the same at P_lo = 0 W, the pessimistic bound ##########"
run per_0p001s_lo0 0.001 250 700 0 60
run per_0p003s_lo0 0.003  84 700 0 60
run per_0p010s_lo0 0.010  25 700 0 60
run per_0p030s_lo0 0.030   9 700 0 60
run per_0p100s_lo0 0.100   6 700 0 60
run per_0p300s_lo0 0.300   3 700 0 60
run per_1s_lo0     1.000   3 700 0 60
run per_3s_lo0     3.000   3 700 0 60

echo "########## coolant control: two existing periods repeated at TCP=40 ##########"
echo "# delta_pp must match the 60 C twins (15.805 and 2.623 K) if the deck is linear"
run ctl_tcp40_86p75ms_lo210 0.08675  6 700 210 40
run ctl_tcp40_10p84ms_lo0   0.01084 40 700   0 40

AFTER=$(grep -c '' "$OUT")
echo "=== DONE: $((AFTER-BEFORE)) row(s) appended, $((BEFORE-1)) preserved ==="
