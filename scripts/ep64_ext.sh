#!/bin/bash
# EP=64 glass: keep walking the buffer until the timeouts vanish.
#
# So far, on ep64_gt with relay=0 throughout:
#   q=533   (2x)   54.182 ms   128415 RTO
#   q=1064  (4x)   52.004 ms   102601 RTO
#   q=2133  (8x)   60.998 ms    64804 RTO   <- slower, and still not clear
#
# Non-monotonic in the same way the NVLink sweep was: more buffer keeps trading
# drops for queueing delay. None of these is quotable under the vanishing-timeout
# rule, so the sweep continues rather than the best-looking one being picked.
#
# 16x and 32x. If 32x still times out the row is reported as "no zero-timeout
# point in the swept range" and the paper says so, rather than quoting a number
# with 10^4 retransmissions.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
mkdir -p "$PAPER" ./gt64x_logs
CSV=$PAPER/cliff_ep64_gt_ext.csv
csv_open "$CSV" "paper_ref,system,cabling,ep,nodes,mb,k,q,q_over_bdp,relayed_pairs,completed,makespan_ms,rtos,wall_s,quotable,status,note"
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
found=0

run () { # k q
  local k=$1 q=$2
  [ "$found" = 1 ] && return 0
  local log=./gt64x_logs/k${k}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep64_gt.txt" \
    timeout 30000 $BIN -logdir "$(_logdir)" -nodes 512 -flowfile "$R/$QME" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos comp st quot
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=sweep
  if [ "$rc" = "124" ]; then st=truncated; elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  quot=no
  if [ "$st" = sweep ] && [ "$rtos" = "0" ]; then quot=yes; found=1; fi
  csv_row "$CSV" paper_ref=cliff system=glassfb cabling=ep64_gt ep=64 nodes=512 mb=8 \
    k="$k" q="$q" q_over_bdp="$k.0" relayed_pairs="$relay" completed="$comp" \
    makespan_ms="$ms" rtos="$rtos" wall_s="$((t1-t0))" quotable="$quot" status="$st" \
    note="EP=64 vanishing-timeout walk continued; 2x/4x/8x all had 6e4-1e5 timeouts"
  printf "  k=%-3s q=%-6s %-10s relay=%-3s %10s ms rtos=%-8s wall=%-5ss quotable=%s [%s]\n" \
    "$k" "$q" "$comp" "$relay" "$ms" "$rtos" "$((t1-t0))" "$quot" "$st"
}

echo "########## EP=64 glass, continuing the buffer walk ##########"
run 16 4267
run 32 8533
[ "$found" = 0 ] && echo "  NOTE: no zero-timeout point up to 32x BDP -- report as such, do not quote a timing row"
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-150
