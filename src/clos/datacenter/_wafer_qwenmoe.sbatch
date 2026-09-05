#!/bin/bash
#SBATCH -J wafer_qwenmoe
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=24G
#SBATCH -t6:00:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_wafer_qwenmoe.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_wafer_qwenmoe.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter
FB_L4=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq4096_mb8_H100.fbuf
FB_L24=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/qwenMoE_paper_dp2tp1pp4_ep64top4_L24_seq4096_mb8_H100.fbuf
WM64=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/wm_ep64.txt
OUT=wafer_qwenmoe_results.csv
echo 'model,nlayers,nodes,thermal_delay_ns,derived_from,final_finish_ps,final_finish_ms,wall_s,timed_out' > $OUT

run_one(){
  local nlayers=$1 fbuf=$2 delay=$3 label=$4 to=$5
  local log=logs/wafer_delay_sweep/qwenmoe_L${nlayers}_${label}.log
  mkdir -p logs/wafer_delay_sweep
  local t0=$(date +%s)
  timeout $to ./htsim_tcp_wafer -nodes 512 -wafer-rows 4 -wafer-cols 4 -intra-delay 78 -thermal-delay $delay -flowfile "$fbuf" -weightmatrix "$WM64" -q 10000 > "$log" 2>&1
  local rc=$?
  local t1=$(date +%s)
  local ok=$(grep -ac 'finished one iter' "$log")
  local ps=$(grep -aoE 'now [0-9]+' "$log" | tail -1 | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  [ "$ok" -eq 0 ] && ps=0
  local timedout="no"; [ "$rc" -eq 124 ] && timedout="yes"
  local ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
  echo "qwen-moe-14.3b,$nlayers,512,$delay,$label,$ps,$ms,$((t1-t0)),$timedout" >> $OUT
  echo "  qwenmoe L${nlayers} $label (delay=${delay}ns) -> ${ms}ms (wall $((t1-t0))s, ok=$ok, timedout=$timedout)"
}

run_one 4 "$FB_L4" 0 baseline 1800
run_one 4 "$FB_L4" 46760000 physical_derived 1800
run_one 24 "$FB_L24" 0 baseline 3000
run_one 24 "$FB_L24" 68330000 physical_derived 3000
echo WAFER_QWENMOE_DONE
