#!/bin/bash
#SBATCH --job-name=prep-pb-pipeline
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:20:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_pbpipe_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_pbpipe_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif

apptainer exec --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO/src/clos" \
  "$SIF" \
  bash -c "
    set -uo pipefail
    cd '$REPO/src/clos'

    gen_synth() {
      python3 -c \"
import json, sys
ep = int(sys.argv[1])
d = {'ep': ep, 'total_dispatch_bytes': 8388608*ep//8, 'total_combine_bytes': 8388608*ep//8,
     'rank_latency_ns': [1000000.0]*ep}
json.dump(d, open(sys.argv[2], 'w'))
\" \"\$1\" \"\$2\"
    }

    echo '=== gen synthetic decode_ep32 / decode_ep64 pb files ==='
    gen_synth 32 /tmp/decode_ep32.json
    gen_synth 64 /tmp/decode_ep64.json
    ./gen_decode_block_smoketest /tmp/decode_ep32.json /tmp/decode_ep32.pb
    ./gen_decode_block_smoketest /tmp/decode_ep64.json /tmp/decode_ep64.pb

    cd datacenter
    mkdir -p ./prep_logs

    echo '=== [EP32, default dragonfly, G=1] .pb load via htsim_tcp_glassfb ==='
    timeout 90 ./htsim_tcp_glassfb -flowfile /tmp/decode_ep32.pb -simtime 5.1 -speed 400000 -nodes 32 \
      -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/wm_ep32.txt \
      -logdir ./prep_logs/ep32_g1/ > ./prep_logs/ep32_g1.log 2>&1
    echo \"[EP32 G1] exit=\$?\"
    grep -i 'GlassFB\|error\|Error\|assert\|Segmentation' ./prep_logs/ep32_g1.log | head -10
    tail -6 ./prep_logs/ep32_g1.log

    echo '=== [EP64, GLASS_INTER=mesh, G=1] .pb load ==='
    mkdir -p ./prep_logs/ep64_mesh_g1
    GLASS_INTER=mesh GLASS_GW_PARALLEL=1 timeout 90 ./htsim_tcp_glassfb -flowfile /tmp/decode_ep64.pb -simtime 5.1 -speed 400000 -nodes 64 \
      -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/wm_ep64.txt \
      -logdir ./prep_logs/ep64_mesh_g1/ > ./prep_logs/ep64_mesh_g1.log 2>&1
    echo \"[EP64 mesh G1] exit=\$?\"
    grep -i 'GlassFB\|gw_parallel\|error\|Error\|assert\|Segmentation' ./prep_logs/ep64_mesh_g1.log | head -10
    tail -6 ./prep_logs/ep64_mesh_g1.log

    echo '=== [EP64, GLASS_INTER=mesh, G=4] .pb load ==='
    mkdir -p ./prep_logs/ep64_mesh_g4
    GLASS_INTER=mesh GLASS_GW_PARALLEL=4 timeout 90 ./htsim_tcp_glassfb -flowfile /tmp/decode_ep64.pb -simtime 5.1 -speed 400000 -nodes 64 \
      -ssthresh 10000 -rttnet 1000 -rttrack 1000 -q 10000 \
      -weightmatrix ../../../test/wm_ep64.txt \
      -logdir ./prep_logs/ep64_mesh_g4/ > ./prep_logs/ep64_mesh_g4.log 2>&1
    echo \"[EP64 mesh G4] exit=\$?\"
    grep -i 'GlassFB\|gw_parallel\|error\|Error\|assert\|Segmentation' ./prep_logs/ep64_mesh_g4.log | head -10
    tail -6 ./prep_logs/ep64_mesh_g4.log
  "
