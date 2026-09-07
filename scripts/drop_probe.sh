#!/bin/bash
# Does the HGX-8 island actually DROP anything, or are its 105 timeouts spurious?
#
# Unanswerable until now: _num_drops was counted in five queue classes and
# printed nowhere, so a log with 13812 timeouts showed exactly as many drop
# lines as one with 73 -- none. htsim_tcp_flat_drop reports the ECN queues'
# total at exit.
#
# Run at the ORIGINAL 100 us floor, unchanged in every other respect, so the
# measurement does not perturb what it measures. Raising the floor cannot answer
# this: at 1000 us a microsecond-RTT flow cannot time out whether or not it is
# losing packets.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test
BIN=./htsim_tcp_flat_drop
mkdir -p ./drop_logs
[ "$(strings $BIN | grep -c dropcount)" -eq 0 ] && { echo "FATAL: $BIN has no drop reporting" >&2; exit 1; }

run () { # tag nodes fb wm nic ign ibw q feed
  local tag=$1 nodes=$2 fb=$3 wm=$4 nic=$5 ign=$6 ibw=$7 q=$8 feed=$9
  local log=./drop_logs/${tag}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=100 timeout 30000 $BIN -logdir "$(_logdir)" -nodes "$nodes" \
    -flowfile "$R/$fb" -speed $((nic * 8000)) -rtt 2000 -port-cap -port-cap-pkts "$feed" \
    -island_gpus "$ign" -island_bw "$ibw" -mtu 1500 -q "$q" \
    -weightmatrix "$T/$wm" > "$log" 2>&1
  local ps ms rtos drops
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  drops=$(grep -m1 -oE "dropcount: [0-9]+" "$log" | awk '{print $2}')
  printf "  %-22s %10s ms   timeouts=%-7s DROPS=%-10s %s\n" \
    "$tag" "$ms" "$rtos" "${drops:-NOT-REPORTED}" \
    "$([ "${drops:-1}" = "0" ] && echo '<- spurious: timeouts with no loss' || echo '')"
}

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf

echo "########## HGX-8 island, drop accounting at the unchanged 100 us floor ##########"
run hgx8_ep32  256 "$L32" wm_ep32.txt 50 8 450 270 135
run hgx8_ep64  512 "$QME" wm_ep64.txt 50 8 450 270 135
echo "########## NVL-64 island EP=16, as a control that reports 0 timeouts ##########"
run nvl64_ep16 128 "$L16" wm_ep16.txt 100 64 900 540 270
echo "=== DONE ==="
