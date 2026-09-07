#!/bin/bash
# Expert-popularity skew sweep at EP=32, on the corrected cabling.
#
# The paper says skew is a swept knob without showing the sweep. The quoted row
# uses test/wm_ep32.txt, which reproduces EXACTLY from
#   gen_weightmatrix.py 32 --skew 1.6 --seed 0
# so the quoted input has a verified producer and the two new matrices differ
# from it ONLY in the exponent: the generator seeds before shuffling, so the
# hot-expert permutation is identical across skew values and skew is isolated
# rather than confounded with the draw.
#
# Everything else is the EP=32 quoted configuration: ep32_gt cabling, placement
# and dim-order routing on, q=2133 (its zero-timeout point), RTO floor 100 us.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
mkdir -p "$PAPER" ./skew_logs
CSV=$PAPER/skew_ep32.csv
csv_open "$CSV" "paper_ref,system,cabling,ep,nodes,mb,q,skew,wm_file,wm_seed,hot_share_pct,relayed_pairs,completed,makespan_ms,rtos,vs_skew16_pct,wall_s,quotable,status,note"
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
BASE=75.542

run () { # skew wmfile
  local sk=$1 wm=$2
  local log=./skew_logs/skew${sk}_${SLURM_JOB_ID:-local}.log t0 t1
  # share of a row's tokens held by its single hottest expert: a one-number
  # summary of what the exponent actually did to the matrix
  local hot
  hot=$(python3 -c "
import ast,sys
m=ast.literal_eval(open('$T/$wm').read())
print('%.1f' % (100.0*sum(max(r) for r in m)/sum(sum(r) for r in m)))")
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep32_gt.txt" \
    timeout 20000 $BIN -logdir "$(_logdir)" -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut -mtu 1500 -q 2133 -weightmatrix "$T/$wm" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos comp st dp quot
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=sweep
  if [ "$rc" = "124" ]; then st=truncated; elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  dp=$(awk -v a="$ms" -v b="$BASE" 'BEGIN{printf "%+.2f", 100*(a-b)/b}')
  quot=no; [ "$st" = sweep ] && [ "$relay" = 0 ] && [ "$rtos" = 0 ] && quot=yes
  csv_row "$CSV" paper_ref=skew system=glassfb cabling=ep32_gt ep=32 nodes=256 mb=8 q=2133 \
    skew="$sk" wm_file="$wm" wm_seed=0 hot_share_pct="$hot" relayed_pairs="$relay" \
    completed="$comp" makespan_ms="$ms" rtos="$rtos" vs_skew16_pct="$dp" wall_s="$((t1-t0))" \
    quotable="$quot" status="$st" \
    note="skew isolated: same seed so the hot-expert permutation is identical across exponents; 1.6 is the quoted row"
  printf "  skew=%-5s hot_share=%-6s%% %-10s relay=%-3s %10s ms (%s%%) rtos=%-7s wall=%ss [%s]\n" \
    "$sk" "$hot" "$comp" "$relay" "$ms" "$dp" "$rtos" "$((t1-t0))" "$st"
}

echo "########## EP=32 skew sweep (1.6 is the quoted row, re-run here as the control) ##########"
run 1.2 wm_ep32_skew1p2.txt
run 1.6 wm_ep32.txt
run 2.0 wm_ep32_skew2p0.txt
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-165
