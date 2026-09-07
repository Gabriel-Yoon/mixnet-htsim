#!/bin/bash
# (0) REGRESSION: with no GLASS_RTO_MIN_US the patched binary must reproduce the
#     pre-patch numbers exactly (46028299484 / 6448818088 ps). If it doesn't, the
#     patch changed behaviour and nothing below is trustworthy.
# (1) Is the 2000->2400 cliff a hardware requirement or a WAN-era timer artifact?
#     RTT here is ~1us (100ns hops); the stock floor is 10ms, ~4 orders above it.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./rto_logs
CSV=$RES/rto_min_sweep.csv
csv_warn_truncate "$CSV" "rto_min_us,inter_bw,makespan_ps,makespan_ms,rtos,rto_waves"
echo "rto_min_us,inter_bw,makespan_ps,makespan_ms,rtos,rto_waves" > "$CSV"

run() {  # rto_us inter  ("" rto_us = unset, i.e. default)
  local rto=$1 inter=$2 label=${1:-default}
  local log=./rto_logs/rto${label}_i${inter}_${SLURM_JOB_ID:-local}.log
  if [ -z "$rto" ]; then
    env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
        GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 \
      timeout 4000 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/coding_prefill_ep64.pb" \
        -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  else
    env GLASS_RTO_MIN_US=$rto GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
        GLASS_OPT_BW=384 GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 \
      timeout 4000 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/coding_prefill_ep64.pb" \
        -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  fi
  local ps ms rto_n waves
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rto_n=$(grep -c '^At ' "$log")
  waves=$(grep '^At ' "$log" | awk '{print $2}' | sort -n | uniq | wc -l)
  echo "$label,$inter,$ps,$ms,$rto_n,$waves" >> "$CSV"
  printf "  RTO_min=%-8s inter=%-5s -> %12s ps (%9s ms)  rtos=%-5s waves=%s\n" \
    "$label" "$inter" "$ps" "$ms" "$rto_n" "$waves"
}

echo "########## (0) regression: default must match pre-patch exactly ##########"
echo "   expect inter=2000 -> 46028299484 ps ; inter=2400 -> 6448818088 ps"
run "" 2000
run "" 2400

echo "########## (1) RTO_min sweep (us) ##########"
for rto in 10000 1000 100 10; do
  for inter in 2000 2400; do
    run "$rto" "$inter"
  done
done
echo "=== DONE rows: $(($(wc -l < "$CSV") - 1)) ==="; cat "$CSV"
