#!/bin/bash
#SBATCH --job-name=smoke-gendecode
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_gendecode_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_gendecode_%j.err

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
    PB=/opt/protobuf-29.0/install
    ABSL=/opt/abseil-cpp-20240722.0/install
    cd '$REPO/src/clos'
    echo '[1/2] regenerate taskgraph.pb.{h,cc} with protoc 29.0'
    \$PB/bin/protoc --cpp_out=. --proto_path=. taskgraph.proto
    ABSL_LIBS=\$(ls \$ABSL/lib/libabsl_*.a | sed -e 's#.*/lib#-l#' -e 's#\.a\$##' | tr '\n' ' ')
    echo '[2/2] compile+link gen_decode_block.cpp against protobuf 29.0 + abseil 20240722'
    g++ -Wall -std=c++17 -O3 -no-pie -fuse-ld=gold \
      -I\$PB/include -I\$ABSL/include -I. \
      gen_decode_block.cpp taskgraph.pb.cc -o gen_decode_block_smoketest \
      -L\$PB/lib -Wl,-rpath,\$PB/lib -L\$ABSL/lib -lprotobuf -lutf8_validity -lutf8_range \
      -Wl,--start-group \$ABSL_LIBS -Wl,--end-group
    echo \"compile+link exit=\$?\"
    ls -la gen_decode_block_smoketest
    echo '--- sanity: run with no args (should print usage, exit 1) ---'
    ./gen_decode_block_smoketest; echo \"run exit=\$?\"
  "
