#!/bin/bash
# Loss count for the hierarchical EP=64 row, so the same gate decides it.
#
# Separate script rather than an edit to quoted_drops.sh, which is executing:
# bash reads a script incrementally and inserting lines shifts every later byte
# offset. Appends to the same CSV by column name, so the gate joins it exactly
# as it joins the others.
#
# The row is interesting because hier at EP=64 posts 254 timeouts against flat's
# 102601 -- it removes almost all the contention and is still 1.7x slower. If its
# drops are zero it becomes quotable while the flat row is not, which the paper
# should state rather than paper over.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/hd_%s_%s_%s' "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
CSV=$PAPER/quoted_row_drops.csv
mkdir -p ./hd_logs
[ -f "$CSV" ] || { echo "FATAL: $CSV missing; run quoted_drops.sh first" >&2; exit 1; }

QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
log=./hd_logs/hier_ep64_q1064_${SLURM_JOB_ID:-local}.log
t0=$(date +%s)
GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep64_gt.txt" \
  timeout 30000 ./htsim_tcp_glassfb_drop -logdir "$(_logdir)" -nodes 512 \
    -flowfile "$R/$QME" -disable-intra-shortcut -a2a_hier -mtu 1500 -q 1064 \
    -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
wall=$(($(date +%s)-t0))
ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
[ -z "$ps" ] && ps=0
ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
rtos=$(grep -c '^At ' "$log")
drops=$(grep -m1 -oE "dropcount: [0-9]+" "$log" | awk '{print $2}')
if   [ -z "$drops" ]; then v=not_reported
elif [ "$drops" = "0" ] && [ "$rtos" = "0" ]; then v=clean
elif [ "$drops" = "0" ]; then v=spurious_timeouts_no_loss
else v=real_loss; fi
csv_row "$CSV" paper_ref=drops system=glassfb_hier ep=64 nodes=512 q=1064 \
  makespan_ms="$ms" rtos="$rtos" drops="${drops:-}" loss_verdict="$v" wall_s="$wall" \
  status=measured \
  note="hierarchical A2A at EP=64; 254 timeouts against the flat row's 102601, so its loss count decides whether it is quotable while flat is not"
printf "  glassfb_hier ep=64 q=1064 -> %s ms  timeouts=%s  drops=%s  %s\n" "$ms" "$rtos" "${drops:-?}" "$v"
