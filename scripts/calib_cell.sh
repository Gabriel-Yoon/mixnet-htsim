#!/bin/bash
# One calibration cell: an 8-GPU synthetic all-to-all at one message size and one
# buffer, on one of the two NVSwitch variants.
#
#   calib_cell.sh <variant a|b> <M bytes> <q pkts> <tag>
#
# variant a: S=18, L=25   -- NVLink4 as the paper models it, per-flow ECMP
# variant b: S=1,  L=450  -- the same aggregate bandwidth, striped
# Both are 450 GB/s per GPU per direction, so the pair isolates per-flow pinning
# from everything else, exactly as the S=1/L=900 control did at NVL-64 scale.
#
# WHAT IS MEASURED. Every ordered pair carries M bytes, so each GPU sends 7M and
# the per-GPU egress is 7M/T. Efficiency is that over 450 GB/s. The published
# targets are 71-82% of line rate at large messages (DeepEP intranode) and a floor
# near 45 us at small ones (8xH100 symmetric-memory all-to-all).
#
# Per-pair bytes are total_dispatch_bytes/ep -- MEASURED on the probe, not derived:
# a graph with total = 56M produced 56 flows of 7M each, so total = 8M gives M per
# pair. The combine is omitted entirely (0 bytes), because a floored one-MSS
# combine is 17% of the payload at M=8kB and would corrupt the small-message cells.
#
# Both link rates divide 1000 GB/s exactly (40 and 2.22... -> post-fix exact
# arithmetic), so these cells are unaffected by the truncation defect either way.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_logdir() { printf './logs/calib_%s_%s_%s' "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
T=../../../test
OUTD=../../../experiments/results/paper/rungs
mkdir -p "$OUTD" ./calib_logs

VAR=$1 M=$2 Q=$3 TAG=$4
case "$VAR" in
  a) SW=18; L=25  ;;
  b) SW=1;  L=450 ;;
  *) echo "unknown variant $VAR" >&2; exit 2 ;;
esac

CSV=$OUTD/${TAG}.csv
csv_open "$CSV" "paper_ref,system,variant,ep,nodes,domain,switches,link_gbps,msg_bytes,q_nvs,q_over_bdp,makespan_ms,T_us,egress_GBps,efficiency,rtos,drops,flows_total,flows_payload,wall_s,status,note"

PB=/tmp/calib_M${M}.pb
if [ ! -s "$PB" ]; then
  python3 - "$M" > /tmp/calib_M${M}.json <<'PY'
import json, sys
M = int(sys.argv[1])
# total/ep is the per-pair size (measured on the probe), so total = 8M for M per pair
print(json.dumps({"ep": 8, "total_dispatch_bytes": 8 * M,
                  "total_combine_bytes": 0, "rank_latency_ns": [0.0] * 8}))
PY
  ../gen_decode_block /tmp/calib_M${M}.json "$PB" >/dev/null 2>&1
fi
[ -s "$PB" ] || { echo "FATAL: no task graph for M=$M" >&2; exit 1; }

LD=$(_logdir); LOG=./calib_logs/${TAG}_${SLURM_JOB_ID:-local}.log
T0=$(date +%s)
GLASS_RTO_MIN_US=100 timeout 20000 ./htsim_tcp_nvswitch_drop -logdir "$LD" -nodes 8 \
    -flowfile "$PB" -nvs_domain 8 -nvs_switches "$SW" -nvs_link "$L" -nvs_lat 250 \
    -nvs_q "$Q" -nvs_ecn_k $((Q / 2)) \
    -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270 -mtu 1500 \
    -weightmatrix "$T/wm_calib8.txt" > "$LOG" 2>&1
RC=$?; T1=$(date +%s)

PS=$(grep "finished one iter" "$LOG" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
[ -z "$PS" ] && PS=0
MS=$(awk -v p="$PS" 'BEGIN{printf "%.6f", p/1e9}')
RTOS=$(grep -c '^At ' "$LOG")
DROPS=$(grep -m1 -oE "dropcount: [0-9]+" "$LOG" | awk '{print $2}')
FT=$(grep -c "^FCT " "$LD/fct_util_out.txt" 2>/dev/null || echo 0)
FP=$(awk '/^FCT/ && $4>1436 {n++} END{print n+0}' "$LD/fct_util_out.txt" 2>/dev/null || echo 0)

ST=sweep
[ "$RC" = "124" ] && ST=truncated
[ "$PS" = "0" ] && ST=no_iteration

read -r TUS EG EFF <<<"$(awk -v ps="$PS" -v m="$M" 'BEGIN{
  if (ps==0) { print "0 0 0"; exit }
  T=ps/1e12; printf "%.3f %.2f %.4f", T*1e6, 7*m/T/1e9, (7*m/T/1e9)/450 }')"

csv_row "$CSV" paper_ref=calib system=calib_nvswitch variant="$VAR" ep=8 nodes=8 \
  domain=8 switches="$SW" link_gbps="$L" msg_bytes="$M" q_nvs="$Q" \
  q_over_bdp="$(awk -v q="$Q" -v l="$L" 'BEGIN{printf "%.2f", (q*1500)/(l*1e9*1e-6)}')" \
  makespan_ms="$MS" T_us="$TUS" egress_GBps="$EG" efficiency="$EFF" \
  rtos="$RTOS" drops="${DROPS:-}" flows_total="$FT" flows_payload="$FP" \
  wall_s="$((T1-T0))" status="$ST" \
  note="synthetic 8-GPU a2a; M per ordered pair; combine omitted; 450 GB/s per GPU per dir in both variants"
csv_close
printf "%s var=%s M=%-9s q=%-6s T=%-10s us egress=%-7s GB/s eff=%-7s rtos=%-6s drops=%s\n" \
  "$TAG" "$VAR" "$M" "$Q" "$TUS" "$EG" "$EFF" "$RTOS" "${DROPS:-}"
