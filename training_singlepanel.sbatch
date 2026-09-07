#!/bin/bash
#SBATCH --job-name=training-1panel
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_train1panel_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_train1panel_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif
FBUF_DIR=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results

apptainer exec --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO/src/clos/datacenter" \
  "$SIF" \
  bash -c '
    set -uo pipefail
    cd '"$REPO"'/src/clos/datacenter
    mkdir -p ./train1panel_logs

    TP4PP4='"$FBUF_DIR"'/mixtral8x7B_paper_dp2tp4pp4_ep8top2_L4_seq1024_mb8_H100.fbuf
    TP2PP8='"$FBUF_DIR"'/mixtral8x7B_paper_dp2tp2pp8_ep8top2_L8_seq1024_mb8_H100.fbuf

    run() {
      local label=$1 fbuf=$2 tp=$3 ep_place=$4 layers=$5
      local log=./train1panel_logs/${label}.log
      if [ "$ep_place" = "1" ]; then
        GLASS_EP_PLACE=1 GLASS_TP=$tp GLASS_EP=8 timeout 1800 ./htsim_tcp_glassfb -flowfile "$fbuf" -simtime 5.1 -speed 1600000 -nodes 256 -mtu 1500 -q 10000 -weightmatrix ../../../test/wm_ep8.txt > "$log" 2>&1
      else
        timeout 1800 ./htsim_tcp_glassfb -flowfile "$fbuf" -simtime 5.1 -speed 1600000 -nodes 256 -mtu 1500 -q 10000 -weightmatrix ../../../test/wm_ep8.txt > "$log" 2>&1
      fi
      local ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
      [ -z "$ps" ] && ps=0
      local ms=$(awk -v p=$ps "BEGIN{printf \"%.3f\", p/1e9}")
      local perlayer=$(awk -v p=$ps -v l=$layers "BEGIN{printf \"%.3f\", (p/1e9)/l}")
      local rto=$(grep -c "^At " "$log")
      echo "$label: total=${ms}ms  per-layer=${perlayer}ms  rtos=$rto  (layers=$layers)"
    }

    echo "=== GLASS_EP_PLACE=1 (EP-aware placement ON) ==="
    run tp4pp4_L4_epaware "$TP4PP4" 4 1 4
    run tp2pp8_L8_epaware "$TP2PP8" 2 1 8

    echo "=== GLASS_EP_PLACE off (native FlexFlow device ordering) ==="
    run tp4pp4_L4_native "$TP4PP4" 4 0 4
    run tp2pp8_L8_native "$TP2PP8" 2 0 8
  '
