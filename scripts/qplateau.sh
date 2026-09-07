#!/bin/bash
# Is the q-sensitivity a property of the TIMEOUT REGIME or of the simulator?
#
# Around q=1064 the makespan moves 7.9% over a 6.7% range of q, non-monotonically
# (1000 -> 88.089, 1032 -> 92.088, 1064 -> 91.367, 1067 -> 85.365). Every one of
# those points still has 1300-1800 timeouts.
#
# From 8x BDP the timeouts vanish and the curve flattens: 2133 -> 75.542 and
# 4267 -> 75.540, two points 2x apart agreeing to 2 parts in 10^5. If the same
# +-3 packet perturbation that moved the timeout-regime points by 7.9% moves
# nothing here, the chaos belongs to the timeout regime, and the quoted rows --
# which are all at zero RTO by the vanishing-timeout rule -- need no band. The
# band would then apply only to the sensitivity rows.
#
# Three points straddling the knee at the same +-1.5% perturbation used before.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./qplat_logs
CSV=$PAPER/qplateau_ep32.csv
csv_open "$CSV" "paper_ref,cabling,ep,nodes,q,q_over_bdp,q_pct_vs_2133,relayed_pairs,completed,makespan_ms,pct_vs_2133,rtos,wall_s,status,note"
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
BASE=75.542

run () {
  local q=$1
  local log=./qplat_logs/q${q}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep32_gt.txt" \
    timeout 10800 ./htsim_tcp_glassfb_pm -logdir "$(_logdir)" -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos comp st qob qp mp
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  qob=$(awk -v q="$q" 'BEGIN{printf "%.2f", (q*1500)/400000}')
  qp=$(awk -v q="$q" 'BEGIN{printf "%+.2f", 100*(q-2133)/2133}')
  mp=$(awk -v m="$ms" -v b="$BASE" 'BEGIN{printf "%+.3f", 100*(m-b)/b}')
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=sensitivity
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  csv_row "$CSV" paper_ref=plateau cabling=portmap_ground_truth ep=32 nodes=256 \
    q="$q" q_over_bdp="$qob" q_pct_vs_2133="$qp" relayed_pairs="$relay" completed="$comp" \
    makespan_ms="$ms" pct_vs_2133="$mp" rtos="$rtos" wall_s="$((t1-t0))" status="$st" \
    note="plateau perturbation; is the q-chaos confined to the timeout regime"
  printf "  q=%-5s (%s%% vs 2133) -> %10s ms (%s%%)  rtos=%-7s [%s]\n" "$q" "$qp" "$ms" "$mp" "$rtos" "$st"
}

echo "########## plateau perturbation, all expected at zero RTO ##########"
for q in 2100 2133 2166; do run "$q"; done
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
