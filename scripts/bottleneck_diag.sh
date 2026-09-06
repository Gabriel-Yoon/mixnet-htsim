#!/bin/bash
# Which resource is actually on the critical path at mb=4? Vary one knob at a
# time from the same baseline; whichever moves the makespan is the bottleneck.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
FB=$R/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb4_H100.fbuf
T=../../../test
mkdir -p ./diag_logs

probe() {  # label elec opt inter
  local label=$1 elec=$2 opt=$3 inter=$4
  local log=./diag_logs/diag_${label}.log
  GLASS_INTER=fb2 GLASS_PANEL=16 GLASS_EP_PLACE=1 GLASS_TP=1 GLASS_EP=16 \
  GLASS_ELEC_BW=$elec GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=1 \
    timeout 1200 ./htsim_tcp_glassfb -nodes 128 -flowfile "$FB" \
      -q 10000 -weightmatrix $T/wm_ep16.txt > "$log" 2>&1
  local ps
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  printf "%-22s elec=%-5s opt=%-4s inter=%-5s -> %s ps (%.3f ms)\n" \
    "$label" "$elec" "$opt" "$inter" "$ps" "$(awk -v p=$ps 'BEGIN{print p/1e9}')"
}

echo "baseline is the published design: elec 1800 / opt 400 / inter 200"
probe baseline            1800 400  200
echo "--- widen ONE knob at a time ---"
probe opt_x2              1800 800  200
probe inter_x8            1800 400  1600
probe elec_x2             3600 400  200
echo "--- shrink ONE knob at a time (a binding resource should hurt) ---"
probe opt_half            1800 200  200
probe inter_half          1800 400  100
probe elec_half            900 400  200
