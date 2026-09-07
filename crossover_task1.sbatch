#!/bin/bash
#SBATCH --job-name=crossover-task1
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=08:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_crossover_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_crossover_%j.err

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
    mkdir -p ../../../experiments/results ./crossover_logs
    R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
    T=../../../test
    CSV=../../../experiments/results/crossover_wg_width.csv
    echo "arm,mb,inter_mode,opt_bw,inter_bw,gw_parallel,makespan_ps,makespan_ms,rtos" > "$CSV"

    run() {
      local arm=$1 mb=$2 mode=$3 opt=$4 inter=$5 g=$6
      local fbuf=$R/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
      local log=./crossover_logs/${arm}_mb${mb}_opt${opt}_inter${inter}_g${g}.log
      GLASS_INTER=$mode GLASS_PANEL=16 GLASS_EP_PLACE=1 GLASS_TP=1 GLASS_EP=16 \
      GLASS_ELEC_BW=1800 GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=$g \
        timeout 3000 ./htsim_tcp_glassfb -nodes 128 -flowfile "$fbuf" \
          -q 10000 -weightmatrix $T/wm_ep16.txt > "$log" 2>&1
      local ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
      [ -z "$ps" ] && ps=0
      local ms=$(awk -v p=$ps "BEGIN{printf \"%.3f\", p/1e9}")
      local rto=$(grep -c "^At " "$log")
      echo "$arm,$mb,$mode,$opt,$inter,$g,$ps,$ms,$rto" >> "$CSV"
      echo "done: $arm mb=$mb $mode opt=$opt inter=$inter G=$g -> ${ms}ms rtos=$rto"
    }

    echo "=== ARM A: controlled ablation, inter held at 200, intra widens ==="
    for MB in 4 8 16 32; do
      for OPT in 400 512 640 896; do
        run armA $MB fb2 $OPT 200 1
      done
    done

    echo "=== ARM B: proposed design point 640/1600 mesh G=4 ==="
    for MB in 4 8 16 32; do
      run armB $MB mesh 640 1600 4
    done

    echo "=== DONE, rows: $(($(wc -l < "$CSV") - 1)) ==="
    cat "$CSV"
  '
