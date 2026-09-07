#!/bin/bash
# THE decisive control for the drop counter: a run that must drop.
#
# The island control reported zero drops at a 10-packet queue, which is
# inconclusive -- its makespan is identical at q=10 and q=270, so it may never
# queue at all, and a counter that cannot fire looks the same as a fabric that
# never drops.
#
# The mesh-cabling cell posts 16068 timeouts. If dropcount is 0 there, the
# counter is broken and every "0 drops" reading so far is worthless. If it is
# large, then zero on the island means what it says.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/gdc_%s_%s_%s' "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps
BIN=./htsim_tcp_glassfb_drop
mkdir -p ./gdc_logs
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

echo "########## mesh cabling, q=1064 -- known to post 16068 timeouts ##########"
log=./gdc_logs/mesh_q1064_${SLURM_JOB_ID:-local}.log
GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
GLASS_OPT_BW=384 GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 \
  timeout 20000 $BIN -logdir "$(_logdir)" -nodes 256 -flowfile "$R/$L32" \
    -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
[ -z "$ps" ] && ps=0
printf "  mesh q=1064 -> %.3f ms  timeouts=%s  DROPS=%s\n" \
  "$(awk -v p=$ps 'BEGIN{print p/1e9}')" "$(grep -c '^At ' "$log")" \
  "$(grep -m1 -oE 'dropcount: [0-9]+' "$log" | awk '{print $2}')"
echo
echo "Counter is trustworthy only if DROPS > 0 here."
