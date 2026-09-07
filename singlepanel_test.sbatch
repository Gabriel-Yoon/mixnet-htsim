#!/bin/bash
#SBATCH --job-name=singlepanel-test
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_1panel_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_1panel_%j.err

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
    mkdir -p ../../../experiments/results ./onepanel_logs
    CSV=../../../experiments/results/mixtral_singlepanel.csv
    echo "workload,config,makespan_ps,makespan_ms,rtos" > "$CSV"

    run_glassfb() {
      local wl=$1 label=$2 panel=$3
      local pb=../../../experiments/pb_workloads/pb/${wl}_ep8.pb
      local wm=../../../test/wm_ep8.txt
      local log=./onepanel_logs/${wl}_${label}.log
      GLASS_PANEL=$panel ./htsim_tcp_glassfb -nodes 8 -flowfile "$pb" -q 10000 -weightmatrix "$wm" > "$log" 2>&1
      local ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
      [ -z "$ps" ] && ps=0
      local ms=$(awk -v p=$ps "BEGIN{printf \"%.3f\", p/1e9}")
      local rto=$(grep -c "^At " "$log")
      echo "$wl,$label,$ps,$ms,$rto" >> "$CSV"
      echo "done: $wl $label -> ${ms}ms rtos=$rto"
    }

    run_fattree() {
      local wl=$1
      local pb=../../../experiments/pb_workloads/pb/${wl}_ep8.pb
      local wm=../../../test/wm_ep8.txt
      local log=./onepanel_logs/${wl}_fattree.log
      ./htsim_tcp_fattree -nodes 8 -flowfile "$pb" -speed 1600000 -mtu 1500 -q 10000 -weightmatrix "$wm" > "$log" 2>&1
      local ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
      [ -z "$ps" ] && ps=0
      local ms=$(awk -v p=$ps "BEGIN{printf \"%.3f\", p/1e9}")
      local rto=$(grep -c "^At " "$log")
      echo "$wl,fattree,$ps,$ms,$rto" >> "$CSV"
      echo "done: $wl fattree -> ${ms}ms rtos=$rto"
    }

    for wl in mixtral_decode mixtral_coding_prefill mixtral_chat_prefill mixtral_agentic_prefill; do
      run_glassfb $wl onepanel_8 8
      run_glassfb $wl split_4x2 4
      run_glassfb $wl split_2x4 2
      run_fattree $wl
    done
    echo "=== DONE ==="
    cat "$CSV"
  '
