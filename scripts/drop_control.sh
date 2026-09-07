#!/bin/bash
# POSITIVE control for the drop counter.
#
# The island probe reports "dropcount: 0" with 105 timeouts, which is the answer
# we want -- and is exactly what a counter that never fires would also report.
# That is the error made earlier with the drop-lines grep: a zero was read as
# evidence of no loss when it was evidence of no reporting.
#
# So: force loss. A 10-packet queue on the same binary and workload MUST overflow.
# If dropcount is > 0 there and 0 in the island run, the counter works and the
# island's timeouts really are lossless. If it is 0 here too, the counter is
# broken and the island result means nothing.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/dropctl_%s_%s_%s' "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test
BIN=./htsim_tcp_flat_drop
mkdir -p ./dropctl_logs
L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf

run () { # tag q feed
  local tag=$1 q=$2 feed=$3
  local log=./dropctl_logs/${tag}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=100 timeout 20000 $BIN -logdir "$(_logdir)" -nodes 128 \
    -flowfile "$R/$L16" -speed 400000 -rtt 2000 -port-cap -port-cap-pkts "$feed" \
    -island_gpus 8 -island_bw 450 -mtu 1500 -q "$q" \
    -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  local ps ms rtos drops
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  drops=$(grep -m1 -oE "dropcount: [0-9]+" "$log" | awk '{print $2}')
  printf "  %-26s q=%-6s -> %10s ms  timeouts=%-8s DROPS=%s\n" "$tag" "$q" "$ms" "$rtos" "${drops:-NOT-REPORTED}"
}

echo "########## positive control: a queue too small not to overflow ##########"
run tiny_queue_q10   10   5
echo "########## the island setting, for comparison on the same binary ##########"
run island_q270     270 135
echo "=== DONE ==="
echo "Counter is trustworthy only if the tiny queue reports DROPS > 0."
