#!/bin/bash
# Bytes per tier for the packet-level incumbent, from the topology's own hops.
#
# GLASS_LOG_FLOWS gives (src, dst, bytes) from TcpSrc::set_flowsize; GLASS_LOG_HOPS
# has NVSwitchTopology::get_paths emit its own classification:
#
#   nvhoplog: <src> <dst> <nvlink_hops> <nic_hops>
#
# In-domain is GPU->switch->GPU, two NVLink hops. Cross-domain rides
# nic_feeder->nic_q->nic_p and touches NO NVLink queue -- so the incumbent's
# in-domain byte count is NOT "everything at both ends of every flow", which is
# what I had assumed before reading the routes.
#
# EP=16 and EP=32, both systems, at the buffers the cliff rows use.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test
BIN=./htsim_tcp_nvswitch_hop
mkdir -p ./tier_logs

if [ "$(strings $BIN 2>/dev/null | grep -c GLASS_LOG_HOPS)" -eq 0 ]; then
  echo "FATAL: $BIN has no GLASS_LOG_HOPS instrumentation -- wrong binary" >&2; exit 1
fi

run () { # tag nodes fb wm D S L nic qn qc
  local tag=$1 nodes=$2 fb=$3 wm=$4 D=$5 S=$6 L=$7 nic=$8 qn=$9 qc=${10}
  local log=./tier_logs/${tag}_${SLURM_JOB_ID:-local}.log t0
  t0=$(date +%s)
  GLASS_LOG_FLOWS=1 GLASS_LOG_HOPS=1 GLASS_RTO_MIN_US=100 \
    timeout 30000 $BIN -logdir "$(_logdir)" -nodes "$nodes" -flowfile "$R/$fb" \
      -nvs_domain "$D" -nvs_switches "$S" -nvs_link "$L" -nvs_lat 250 \
      -nvs_q "$qn" -nvs_ecn_k $((qn / 2)) \
      -speed $((nic * 8000)) -rtt 2000 -q "$qc" -port-cap-pkts $((qc / 2)) -mtu 1500 \
      -weightmatrix "$T/$wm" > "$log" 2>&1
  grep "^flowlog: "  "$log" > ./tier_logs/${tag}.flowlog
  grep "^nvhoplog: " "$log" > ./tier_logs/${tag}.nvhoplog
  printf "  %-18s flows=%-9s pairs_routed=%-8s wall=%ss\n" \
    "$tag" "$(wc -l < ./tier_logs/${tag}.flowlog)" "$(wc -l < ./tier_logs/${tag}.nvhoplog)" \
    "$(($(date +%s)-t0))"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

echo "########## NVL-64 ##########"
run tier_nvl64_ep16 128 "$L16" wm_ep16.txt 64 18 50    100 544  540
run tier_nvl64_ep32 256 "$L32" wm_ep32.txt 64 18 50    100 544  540
run tier_nvl64_ep64 512 "$QME" wm_ep64.txt 64 18 50    100 2176 540
echo "########## HGX-8 ##########"
run tier_hgx8_ep16  128 "$L16" wm_ep16.txt  8  4 112.5  50 1224 270
run tier_hgx8_ep32  256 "$L32" wm_ep32.txt  8  4 112.5  50 1224 270
run tier_hgx8_ep64  512 "$QME" wm_ep64.txt  8  4 112.5  50 1224 270
echo "=== DONE ==="
