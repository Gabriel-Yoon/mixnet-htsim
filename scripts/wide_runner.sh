#!/bin/bash
# Shared runner for the wide-design (640 intra / 1600 inter) sweeps.
#
# FOOTGUN this exists to avoid: the published sweep commands never set
# GLASS_OPT_BW, so every current-design row silently used the 400 GB/s default.
# Any wide run MUST set GLASS_OPT_BW=640 explicitly or it gets the old intra
# width with the new inter bandwidth, which is meaningless.
#
# Usage: wide_runner.sh <task>   where task in {task2, task3a, task3b}
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
RES=../../../experiments/results
PB=../../../experiments/pb_workloads/pb
T=../../../test
mkdir -p "$RES" ./wide_logs

WORKLOADS="decode coding_prefill chat_prefill agentic_prefill"

# iso-power fair speed for the fat-tree side, from main.tex's own basis:
#   Glass-FB  7.66 TB/s x 8 = 61280 Gb/s x 1.15 pJ/bit = 70.47 W   (reproduces "~70 W")
#   fat-tree  r x 20 pJ/bit = 70.47 W  ->  r = 3523.6 Gb/s = 440.4 GB/s
# -speed is in Mbps, so 440.4 x 8000 = 3523600.
FAIR_SPEED_MBPS=3523600

emit() { echo "$1" >> "$2"; echo "done: $1"; }

parse() {  # $1 = log path -> prints "ps ms rtos"
  local ps ms rto
  ps=$(grep "finished one iter" "$1" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rto=$(grep -c '^At ' "$1")
  echo "$ps $ms $rto"
}

run_glassfb_wide() {  # wl ep nodes csv
  local wl=$1 ep=$2 nodes=$3 csv=$4
  local log=./wide_logs/glassfb_wide_${wl}_ep${ep}.log
  GLASS_INTER=mesh GLASS_OPT_BW=640 GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
    timeout 5400 ./htsim_tcp_glassfb -nodes "$nodes" -flowfile "$PB/${wl}_ep${ep}.pb" \
      -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep${ep}.txt" > "$log" 2>&1
  read -r ps ms rto <<< "$(parse "$log")"
  emit "$wl,$ep,$nodes,glassfb_mesh,wide,640,1600,4,,$ps,$ms,$rto" "$csv"
}

run_baseline_wide() {  # bin label wl ep nodes csv
  local bin=$1 label=$2 wl=$3 ep=$4 nodes=$5 csv=$6
  local log=./wide_logs/${label}_wide_${wl}_ep${ep}.log
  timeout 5400 "$bin" -nodes "$nodes" -flowfile "$PB/${wl}_ep${ep}.pb" \
    -speed "$FAIR_SPEED_MBPS" -mtu 1500 -q 10000 \
    -weightmatrix "$T/wm_ep${ep}.txt" > "$log" 2>&1
  read -r ps ms rto <<< "$(parse "$log")"
  emit "$wl,$ep,$nodes,$label,wide,,,,$FAIR_SPEED_MBPS,$ps,$ms,$rto" "$csv"
}

HDR="workload,ep,nodes,topology,design,opt_bw,inter_bw,G,fair_speed_mbps,makespan_ps,makespan_ms,rtos"

case "$1" in
  task2)   # EP 32/64 at the wide design
    CSV=$RES/serving_sweep_wide.csv; echo "$HDR" > "$CSV"
    for wl in $WORKLOADS; do for ep in 32 64; do run_glassfb_wide "$wl" "$ep" "$ep" "$CSV"; done; done
    ;;
  task3a)  # EP 128/144 scale at the wide design
    CSV=$RES/serving_sweep_scale_wide.csv; echo "$HDR" > "$CSV"
    for wl in $WORKLOADS; do for ep in 128 144; do run_glassfb_wide "$wl" "$ep" "$ep" "$CSV"; done; done
    ;;
  task3b)  # iso-power baselines at the wide design's power point
    CSV=$RES/serving_sweep_isopower_wide.csv; echo "$HDR" > "$CSV"
    for wl in $WORKLOADS; do for ep in 32 64; do
      run_baseline_wide ./htsim_tcp_fattree fattree "$wl" "$ep" "$ep" "$CSV"
      run_baseline_wide ./htsim_tcp_flat    flat    "$wl" "$ep" "$ep" "$CSV"
    done; done
    ;;
  *) echo "usage: $0 {task2|task3a|task3b}"; exit 1;;
esac
echo "=== $1 DONE, rows: $(($(wc -l < "$CSV") - 1)) ==="
cat "$CSV"
