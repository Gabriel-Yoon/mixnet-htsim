#!/bin/bash
#SBATCH --job-name=glassfb-gw-smoke
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:15:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_gwsmoke_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_gwsmoke_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif
FBUF_DIR=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
TWOSTAGE_FBUF="$FBUF_DIR/mixtral8x22B_paper_dp2tp8pp8_ep8top2_L8_seq4096_mb8_H100_fixed.fbuf"

apptainer exec --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO/src/clos/datacenter" \
  "$SIF" \
  bash -c "
    set -uo pipefail
    cd '$REPO/src/clos/datacenter'
    SIMTIME=20.1
    mkdir -p ./smoke_logs

    echo '=== [C] glassfb GLASS_INTER=mesh GLASS_GW_PARALLEL=1 (64 panels, mesh, single gateway) ==='
    mkdir -p ./smoke_logs/glassfb_mesh_gw1
    GLASS_INTER=mesh GLASS_GW_PARALLEL=1 timeout 180 ./htsim_tcp_glassfb -flowfile '$TWOSTAGE_FBUF' -simtime \$SIMTIME -speed 100000 -nodes 1024 \
      -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./smoke_logs/glassfb_mesh_gw1/ > ./smoke_logs/glassfb_mesh_gw1.log 2>&1
    echo \"[C] exit=\$?\"
    grep -i 'GlassFB\|gw_parallel\|GW_PARALLEL\|error\|Error\|assert\|Segmentation' ./smoke_logs/glassfb_mesh_gw1.log | head -20
    tail -8 ./smoke_logs/glassfb_mesh_gw1.log

    echo '=== [D] glassfb GLASS_INTER=mesh GLASS_GW_PARALLEL=4 (64 panels, mesh, 4-way gateway) ==='
    mkdir -p ./smoke_logs/glassfb_mesh_gw4
    GLASS_INTER=mesh GLASS_GW_PARALLEL=4 timeout 180 ./htsim_tcp_glassfb -flowfile '$TWOSTAGE_FBUF' -simtime \$SIMTIME -speed 100000 -nodes 1024 \
      -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./smoke_logs/glassfb_mesh_gw4/ > ./smoke_logs/glassfb_mesh_gw4.log 2>&1
    echo \"[D] exit=\$?\"
    grep -i 'GlassFB\|gw_parallel\|GW_PARALLEL\|error\|Error\|assert\|Segmentation' ./smoke_logs/glassfb_mesh_gw4.log | head -20
    tail -8 ./smoke_logs/glassfb_mesh_gw4.log
  "
