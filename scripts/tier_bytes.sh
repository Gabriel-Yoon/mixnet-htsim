#!/bin/bash
# Bytes per tier for the energy table: run once with both logs on.
#
# GLASS_LOG_FLOWS gives every flow's (src, dst, bytes) from TcpSrc::set_flowsize,
# the one choke point all nine collectives pass through. GLASS_LOG_HOPS gives the
# topology's OWN per-tier hop classification for each (src, dst) pair, using the
# same adjacent_link predicate the link construction uses. Multiplying the two
# gives bytes x hops per tier without reimplementing gw(), relay_for() or the
# port-map graph -- so the split cannot drift from the routing it describes.
#
# EP=16 and EP=32, the two rows the energy table quotes. Same configuration as
# the cliff rows so the byte counts belong to the makespans we publish.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps
BIN=./htsim_tcp_glassfb_pmhop
mkdir -p ./tier_logs

if [ "$(strings $BIN 2>/dev/null | grep -c GLASS_LOG_HOPS)" -eq 0 ]; then
  echo "FATAL: $BIN has no GLASS_LOG_HOPS instrumentation -- wrong binary" >&2; exit 1
fi

run () { # tag nodes fbuf wm map q
  local tag=$1 nodes=$2 fb=$3 wm=$4 map=$5 q=$6
  local log=./tier_logs/${tag}_${SLURM_JOB_ID:-local}.log t0
  t0=$(date +%s)
  GLASS_LOG_FLOWS=1 GLASS_LOG_HOPS=1 \
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/$map" \
    timeout 20000 $BIN -logdir "$(_logdir)" -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/$wm" > "$log" 2>&1
  grep "^flowlog: " "$log" > ./tier_logs/${tag}.flowlog
  grep "^hoplog: "  "$log" > ./tier_logs/${tag}.hoplog
  printf "  %-14s flows=%-9s pairs_routed=%-8s wall=%ss\n" \
    "$tag" "$(wc -l < ./tier_logs/${tag}.flowlog)" "$(wc -l < ./tier_logs/${tag}.hoplog)" \
    "$(($(date +%s)-t0))"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

echo "########## EP=16 (quoted at q=1064, its zero-RTO point) ##########"
run tier_ep16 128 "$L16" wm_ep16.txt ep16_0_8_4.txt 1064
echo "########## EP=32 (quoted at q=2133, its zero-RTO point) ##########"
run tier_ep32 256 "$L32" wm_ep32.txt ep32_gt.txt   2133
echo "=== DONE ==="
