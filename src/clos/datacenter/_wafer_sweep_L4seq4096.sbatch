#!/bin/bash
#SBATCH -J wafer_sweep_L4seq4096
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=16G
#SBATCH -t3:00:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_wafer_sweep_L4seq4096.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_wafer_sweep_L4seq4096.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter
FB_LLAMA=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq4096_mb8_H100.fbuf
FB_MIXTRAL=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/mixtral8x7B_paper_dp2tp4pp4_ep8top2_L4_seq4096_mb8_H100.fbuf
WM16=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/wm_ep16.txt
WM8=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/num_global_tokens_per_expert.txt
OUT=wafer_sweep_L4seq4096_results.csv
echo 'model,nodes,thermal_delay_ns,final_finish_ps,final_finish_ms,wall_s' > $OUT

run_one(){
  local model=$1 nodes=$2 fbuf=$3 wm=$4 delay=$5
  local log=logs/wafer_delay_sweep/sweep_L4seq4096_${model}_${delay}.log
  mkdir -p logs/wafer_delay_sweep
  local t0=$(date +%s)
  timeout 2400 ./htsim_tcp_wafer -nodes $nodes -wafer-rows 4 -wafer-cols 4 -intra-delay 78 -thermal-delay $delay -flowfile "$fbuf" -weightmatrix "$wm" -q 10000 > "$log" 2>&1
  local t1=$(date +%s)
  local ok=$(grep -ac 'finished one iter' "$log")
  local ps=$(grep -aoE 'now [0-9]+' "$log" | tail -1 | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  [ "$ok" -eq 0 ] && ps=0
  local ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
  echo "$model,$nodes,$delay,$ps,$ms,$((t1-t0))" >> $OUT
  echo "  $model delay=${delay}ns -> ${ms}ms (wall $((t1-t0))s, ok=$ok)"
}

for delay in 1000000 10000000 100000000 300000000; do
  run_one llama-moe-6.7b 128 "$FB_LLAMA" "$WM16" $delay
  run_one mixtral8x7b 256 "$FB_MIXTRAL" "$WM8" $delay
done
echo WAFER_SWEEP_L4SEQ4096_DONE
