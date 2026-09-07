#!/bin/bash
# Is the 2000->2400 "cliff" a hardware requirement or a TCP timeout threshold?
#
# Evidence it is the latter: RTO events in the 1600 run arrive in discrete waves
# (37 @ 11ms, 18 @ 23ms, 11 @ 42ms) against ffapp.cpp's hardcoded
# _rto = timeFromMs(10). Makespan is quantized in RTO_min units, which explains
# the bit-identical plateaus, more-bandwidth-hurting, and less-bandwidth-helping.
#
# If the cliff stays between 2000 and 2400 across every transport setting, the
# provisioning requirement is physical. If it moves, the honest claim becomes
# "above the provisioning where the inter-panel link exits the timeout regime
# (transport-dependent; X at our settings)".
#
# NOTE: RTO_min itself is NOT sweepable -- hardcoded timeFromMs(10)/timeFromMs(1)
# in ffapp.cpp with no env knob. Would need a source patch.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./transport_logs
CSV=$RES/transport_sensitivity.csv
csv_warn_truncate "$CSV" "knob,value,inter_bw,makespan_ps,makespan_ms,rtos,rto_waves"
echo "knob,value,inter_bw,makespan_ps,makespan_ms,rtos,rto_waves" > "$CSV"

run() {  # knob value inter q ecn mtu
  local knob=$1 val=$2 inter=$3 q=$4 ecn=$5 mtu=$6
  local log=./transport_logs/${knob}${val}_i${inter}.log
  env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
      GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 GLASS_ECN_K=$ecn \
    timeout 4000 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/coding_prefill_ep64.pb" \
      -mtu "$mtu" -q "$q" -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  local ps ms rto waves
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rto=$(grep -c '^At ' "$log")
  waves=$(grep '^At ' "$log" | awk '{print $2}' | sort -n | uniq | wc -l)
  echo "$knob,$val,$inter,$ps,$ms,$rto,$waves" >> "$CSV"
  printf "  %-8s=%-6s inter=%-5s -> %9s ms  rtos=%-5s waves=%s\n" "$knob" "$val" "$inter" "$ms" "$rto" "$waves"
}

for inter in 2000 2400; do
  echo "########## inter=$inter ##########"
  echo "-- baseline --"
  run base    10000 "$inter" 10000 50 1500
  echo "-- buffer depth (-q) --"
  run q        5000 "$inter"  5000 50 1500
  run q       20000 "$inter" 20000 50 1500
  echo "-- ECN marking threshold --"
  run ecnk       10 "$inter" 10000 10 1500
  run ecnk       25 "$inter" 10000 25 1500
  run ecnk      100 "$inter" 10000 100 1500
  echo "-- MTU / burst granularity --"
  run mtu      9000 "$inter" 10000 50 9000
done
echo "=== DONE rows: $(($(wc -l < "$CSV") - 1)) ==="; cat "$CSV"
