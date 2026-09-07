#!/bin/bash
#SBATCH --job-name=baseline-sweep
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_baseline_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_baseline_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif

apptainer exec --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO/src/clos/datacenter" \
  "$SIF" \
  bash -c '
    set -uo pipefail
    cd '"$REPO"'/src/clos/datacenter
    mkdir -p ../../../experiments/results ./baseline_logs
    CSV=../../../experiments/results/baseline_sweep.csv
    echo "workload,ep,nodes,topology,bw_gbps,makespan_ps,makespan_ms,rtos" > "$CSV"

    run_topo() {
      local bin=$1 wl=$2 ep=$3 nodes=$4 bw=$5 label=$6
      local pb=../../../experiments/pb_workloads/pb/${wl}_ep${ep}.pb
      local wm=../../../test/wm_ep${ep}.txt
      local log=./baseline_logs/${label}_${wl}_ep${ep}_bw${bw}.log
      local speed_mbps=$(awk -v b=$bw "BEGIN{printf \"%d\", b*8000}")
      "$bin" -nodes $nodes -flowfile "$pb" -speed $speed_mbps -mtu 1500 -q 10000 -weightmatrix "$wm" > "$log" 2>&1
      local ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
      [ -z "$ps" ] && ps=0
      local ms=$(awk -v p=$ps "BEGIN{printf \"%.3f\", p/1e9}")
      local rto=$(grep -c "^At " "$log")
      echo "$wl,$ep,$nodes,$label,$bw,$ps,$ms,$rto" >> "$CSV"
      echo "done: $label $wl ep$ep bw$bw -> ${ms}ms rtos=$rto"
    }

    for wl in decode coding_prefill chat_prefill agentic_prefill; do
      for bw in 400 800 1600; do
        run_topo ./htsim_tcp_fattree $wl 32 32 $bw fattree
        run_topo ./htsim_tcp_fattree $wl 64 64 $bw fattree
        run_topo ./htsim_tcp_flat $wl 32 32 $bw flat
        run_topo ./htsim_tcp_flat $wl 64 64 $bw flat
      done
    done
    echo "=== DONE, row count: $(($(wc -l < "$CSV") - 1)) ==="
  '
