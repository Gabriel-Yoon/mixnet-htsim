#!/bin/bash
#SBATCH -J wafer_scaling_final
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=24G
#SBATCH -t6:00:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_wafer_scaling_final.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_wafer_scaling_final.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter
FB_LLAMA_L4=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq4096_mb8_H100.fbuf
FB_MIXTRAL_L4=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/mixtral8x7B_paper_dp2tp4pp4_ep8top2_L4_seq4096_mb8_H100.fbuf
FB_LLAMA_L32=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/llamaMoE_paper_dp2tp1pp4_ep16top2_L32_seq4096_mb8_H100.fbuf
FB_MIXTRAL_L32=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/mixtral8x7B_paper_dp2tp4pp4_ep8top2_L32_seq4096_mb8_H100.fbuf
WM16=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/wm_ep16.txt
WM8=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/num_global_tokens_per_expert.txt
OUT=wafer_scaling_final_results.csv
echo 'model,nlayers,nodes,thermal_delay_ns,derived_from,final_finish_ps,final_finish_ms,wall_s,timed_out' > $OUT

run_one(){
  local model=$1 nlayers=$2 nodes=$3 fbuf=$4 wm=$5 delay=$6 label=$7 to=$8
  local log=logs/wafer_delay_sweep/scaling_${model}_L${nlayers}_${label}.log
  mkdir -p logs/wafer_delay_sweep
  local t0=$(date +%s)
  timeout $to ./htsim_tcp_wafer -nodes $nodes -wafer-rows 4 -wafer-cols 4 -intra-delay 78 -thermal-delay $delay -flowfile "$fbuf" -weightmatrix "$wm" -q 10000 > "$log" 2>&1
  local rc=$?
  local t1=$(date +%s)
  local ok=$(grep -ac 'finished one iter' "$log")
  local ps=$(grep -aoE 'now [0-9]+' "$log" | tail -1 | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  [ "$ok" -eq 0 ] && ps=0
  local timedout="no"; [ "$rc" -eq 124 ] && timedout="yes"
  local ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
  echo "$model,$nlayers,$nodes,$delay,$label,$ps,$ms,$((t1-t0)),$timedout" >> $OUT
  echo "  $model L${nlayers} $label (delay=${delay}ns) -> ${ms}ms (wall $((t1-t0))s, ok=$ok, timedout=$timedout)"
}

# corrected L4 (seq4096, matching Table 2) -- new headline numbers
run_one llama-moe-6.7b 4 128 "$FB_LLAMA_L4" "$WM16" 0 baseline 900
run_one mixtral8x7b 4 256 "$FB_MIXTRAL_L4" "$WM8" 0 baseline 900
run_one llama-moe-6.7b 4 128 "$FB_LLAMA_L4" "$WM16" 47420000 physical_derived 900
run_one mixtral8x7b 4 256 "$FB_MIXTRAL_L4" "$WM8" 48660000 physical_derived 900

# full 32-layer scaling validation
run_one llama-moe-6.7b 32 128 "$FB_LLAMA_L32" "$WM16" 0 baseline 3000
run_one mixtral8x7b 32 256 "$FB_MIXTRAL_L32" "$WM8" 0 baseline 3000
run_one llama-moe-6.7b 32 128 "$FB_LLAMA_L32" "$WM16" 96870000 physical_derived 3000
run_one mixtral8x7b 32 256 "$FB_MIXTRAL_L32" "$WM8" 173850000 physical_derived 3000
echo WAFER_SCALING_FINAL_DONE
