#!/bin/bash
# Domain-size cliff as a CURVE, not a point: EP = 8/16/32/64 against
#   nvl4_dom8   8-GPU NVLink4 island, 450 GB/s crossbar, 50 GB/s scale-out
#               (400G ConnectX-7, H100 generation)
#   nvl5_dom64  64-GPU NVL72 domain, 900 GB/s crossbar, 100 GB/s scale-out
#               (800G Ethernet, GB200 generation, per MixNet SIGCOMM'25 S8,
#                which assigns 64 of 72 for power-of-2 parallelism)
#   glassfb     our panel, wide design 640/1600 mesh G=4
#
# EP=8 is the null control: fits every domain, so all three should be close.
# EP=16 fits us and dom64 but not dom8 -> dom8 falls off the cliff.
# EP=32/64 fit only dom64 -> we expect to LOSE to dom64 on raw A2A.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb
T=../../../test
RES=../../../experiments/results
mkdir -p "$RES" ./cliff_logs
CSV=$RES/domain_cliff.csv
echo "workload,ep,nodes,config,domain,intra_bw,scaleout_bw,makespan_ps,makespan_ms,rtos" > "$CSV"

run() {  # label domain pcols intra scaleout wl ep  [extra env pairs...]
  local label=$1 dom=$2 pcols=$3 intra=$4 so=$5 wl=$6 ep=$7
  local log=./cliff_logs/${label}_${wl}_ep${ep}.log
  if [ "$label" = "glassfb" ]; then
    env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=640 \
        GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
      timeout 3000 ./htsim_tcp_glassfb -nodes "$ep" -flowfile "$PB/${wl}_ep${ep}.pb" \
        -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep${ep}.txt" > "$log" 2>&1
  else
    env GLASS_PANEL=$dom GLASS_PCOLS=$pcols \
        GLASS_ELEC_BW=$intra GLASS_OPT_BW=$intra GLASS_INTER_BW=$so \
        GLASS_ELEC_LAT=500 GLASS_OPT_LAT=500 GLASS_INTER_LAT=500 \
      timeout 3000 ./htsim_tcp_glassfb -nodes "$ep" -flowfile "$PB/${wl}_ep${ep}.pb" \
        -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep${ep}.txt" > "$log" 2>&1
  fi
  local ps ms rto
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rto=$(grep -c '^At ' "$log")
  echo "$wl,$ep,$ep,$label,$dom,$intra,$so,$ps,$ms,$rto" >> "$CSV"
  echo "done: $label $wl ep=$ep -> ${ms}ms rtos=$rto"
}

for wl in decode coding_prefill chat_prefill agentic_prefill; do
  for ep in 8 16 32 64; do
    run nvl4_dom8  8  8  450 50  "$wl" "$ep"
    run nvl5_dom64 64 64 900 100 "$wl" "$ep"
    run glassfb    16 4  640 1600 "$wl" "$ep"
  done
done
echo "=== DONE, rows: $(($(wc -l < "$CSV") - 1)) ==="
cat "$CSV"
