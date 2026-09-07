#!/bin/bash
#SBATCH --job-name=mixnet-tests
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_tests_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_tests_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif
FBUF_DIR=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results

# Real fbuf files on PACE matching the degrees the original scripts expect
# (the exact filenames the scripts reference were never committed to the repo).
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
    echo '=== [1/4] mixtral_8x22B_fattree (2-stage) ==='
    mkdir -p ./logs/mixtral8x22B_8_fattree_100_num_global_tokens_per_expert/
    ./htsim_tcp_fattree -flowfile '$TWOSTAGE_FBUF' -simtime 36000.1 -speed 100000 -nodes 1024 \
      -ofile nwsim_linkft_100_num_global_tokens_per_expert.txt -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./logs/mixtral8x22B_8_fattree_100_num_global_tokens_per_expert/ \
      > ./logs/mixtral8x22B_8_fattree_100_num_global_tokens_per_expert/output.log 2>&1
    echo \"exit=\$? (see output.log)\"

    echo '=== [2/4] mixtral_8x22B_mixnet (2-stage) ==='
    mkdir -p ./logs/mixtral8x22B_8_mixnet_100_num_global_tokens_per_expert/
    ./htsim_tcp_mixnet -simtime 3600.1 -flowfile '$TWOSTAGE_FBUF' -speed 100000 \
      -ocs_file nwsim_ocs_100.txt -ecs_file nwsim_ecs_100.txt -nodes 1024 -ssthresh 10000 -rtt 1000 -q 10000 \
      -dp_degree 2 -tp_degree 8 -pp_degree 8 -ep_degree 8 -rdelay 25 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./logs/mixtral8x22B_8_mixnet_100_num_global_tokens_per_expert/ \
      > ./logs/mixtral8x22B_8_mixnet_100_num_global_tokens_per_expert/output.log 2>&1
    echo \"exit=\$? (see output.log)\"

    echo '=== [3/4] onestage_mixtral_8x22B_fattree ==='
    mkdir -p ./logs/mixtral8x22B_onestage_8_fattree_100_num_global_tokens_per_expert/
    ./htsim_tcp_fattree -flowfile '$ONESTAGE_FBUF' -simtime 36000.1 -speed 100000 -nodes 512 \
      -ofile nwsim_linkft_100_num_global_tokens_per_expert.txt -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./logs/mixtral8x22B_onestage_8_fattree_100_num_global_tokens_per_expert/ \
      > ./logs/mixtral8x22B_onestage_8_fattree_100_num_global_tokens_per_expert/output.log 2>&1
    echo \"exit=\$? (see output.log)\"

    echo '=== [4/4] onestage_mixtral_8x22B_mixnet ==='
    mkdir -p ./logs/mixtral8x22B_onestage_8_mixnet_100_num_global_tokens_per_expert/
    ./htsim_tcp_mixnet -simtime 3600.1 -flowfile '$ONESTAGE_FBUF' -speed 100000 \
      -ocs_file nwsim_ocs_100.txt -ecs_file nwsim_ecs_100.txt -nodes 512 -ssthresh 10000 -rtt 1000 -q 10000 \
      -dp_degree 2 -tp_degree 8 -pp_degree 1 -ep_degree 8 -rdelay 25 \
      -weightmatrix ../../../test/num_global_tokens_per_expert.txt \
      -logdir ./logs/mixtral8x22B_onestage_8_mixnet_100_num_global_tokens_per_expert/ \
      > ./logs/mixtral8x22B_onestage_8_mixnet_100_num_global_tokens_per_expert/output.log 2>&1
    echo \"exit=\$? (see output.log)\"
  "
