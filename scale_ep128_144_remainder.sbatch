#!/bin/bash
#SBATCH --job-name=scale-remainder
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_scaleremainder_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_scaleremainder_%j.err

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
    CSV=../../../experiments/results/serving_sweep_scale.csv

    run_topo() {
      local wl=$1 ep=$2 nodes=$3 bw=$4 g=$5
      local pb=../../../experiments/pb_workloads/pb/${wl}_ep${ep}.pb
      local wm=../../../test/wm_ep${ep}.txt
      local log=./scale_logs/${wl}_ep${ep}_bw${bw}_g${g}.log
      GLASS_INTER=mesh GLASS_INTER_BW=$bw GLASS_GW_PARALLEL=$g \
        ./htsim_tcp_glassfb -nodes $nodes -flowfile "$pb" -q 10000 -weightmatrix "$wm" > "$log" 2>&1
      local ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
      [ -z "$ps" ] && ps=0
      local ms=$(awk -v p=$ps "BEGIN{printf \"%.3f\", p/1e9}")
      local rto=$(grep -c "^At " "$log")
      echo "$wl,$ep,$nodes,glassfb_mesh,$bw,$g,$ps,$ms,$rto" >> "$CSV"
      echo "done: $wl ep$ep bw$bw G$g -> ${ms}ms rtos=$rto"
    }

    run_topo agentic_prefill 144 144 800 4
    run_topo agentic_prefill 128 128 1600 1
    run_topo agentic_prefill 128 128 1600 4
    run_topo agentic_prefill 144 144 1600 1
    run_topo agentic_prefill 144 144 1600 4
    echo "=== DONE, row count: $(($(wc -l < "$CSV") - 1)) ==="
  '
