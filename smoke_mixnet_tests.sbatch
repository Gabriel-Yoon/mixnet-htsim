#!/bin/bash
#SBATCH --job-name=mixnet-smoke
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:15:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_smoke_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_smoke_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif
FBUF_DIR=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
TWOSTAGE_FBUF="$FBUF_DIR/mixtral8x22B_paper_dp2tp8pp8_ep8top2_L8_seq4096_mb8_H100.fbuf"
ONESTAGE_FBUF="$FBUF_DIR/H200/mixtral8x22B_fullmeasure_dp2tp8pp1ep8_mb8_1L_seq1024_H200.fbuf"

apptainer exec --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO/src/clos/datacenter" \
  "$SIF" \
  bash -c "
    set -uo pipefail
    cd '$REPO/src/clos/datacenter'
    SIMTIME=50.1
    mkdir -p ./smoke_logs

    echo '=== [1/4] fattree (2-stage) smoke ==='
    timeout 120 ./htsim_tcp_fattree -flowfile '$TWOSTAGE_FBUF' -simtime \$SIMTIME -speed 100000 -nodes 1024 \
      -ofile ./smoke_logs/nwsim_linkft.txt -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./smoke_logs/fattree_2stage/ > ./smoke_logs/fattree_2stage.log 2>&1
    echo \"[1/4] exit=\$?\"
    tail -5 ./smoke_logs/fattree_2stage.log

    echo '=== [2/4] mixnet (2-stage) smoke ==='
    timeout 120 ./htsim_tcp_mixnet -simtime \$SIMTIME -flowfile '$TWOSTAGE_FBUF' -speed 100000 \
      -ocs_file ./smoke_logs/nwsim_ocs.txt -ecs_file ./smoke_logs/nwsim_ecs.txt -nodes 1024 -ssthresh 10000 -rtt 1000 -q 10000 \
      -dp_degree 2 -tp_degree 8 -pp_degree 8 -ep_degree 8 -rdelay 25 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./smoke_logs/mixnet_2stage/ > ./smoke_logs/mixnet_2stage.log 2>&1
    echo \"[2/4] exit=\$?\"
    tail -5 ./smoke_logs/mixnet_2stage.log

    echo '=== [3/4] fattree (onestage) smoke ==='
    timeout 120 ./htsim_tcp_fattree -flowfile '$ONESTAGE_FBUF' -simtime \$SIMTIME -speed 100000 -nodes 512 \
      -ofile ./smoke_logs/nwsim_linkft_onestage.txt -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./smoke_logs/fattree_onestage/ > ./smoke_logs/fattree_onestage.log 2>&1
    echo \"[3/4] exit=\$?\"
    tail -5 ./smoke_logs/fattree_onestage.log

    echo '=== [4/4] mixnet (onestage) smoke ==='
    timeout 120 ./htsim_tcp_mixnet -simtime \$SIMTIME -flowfile '$ONESTAGE_FBUF' -speed 100000 \
      -ocs_file ./smoke_logs/nwsim_ocs_onestage.txt -ecs_file ./smoke_logs/nwsim_ecs_onestage.txt -nodes 512 -ssthresh 10000 -rtt 1000 -q 10000 \
      -dp_degree 2 -tp_degree 8 -pp_degree 1 -ep_degree 8 -rdelay 25 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./smoke_logs/mixnet_onestage/ > ./smoke_logs/mixnet_onestage.log 2>&1
    echo \"[4/4] exit=\$?\"
    tail -5 ./smoke_logs/mixnet_onestage.log
  "
