#!/bin/bash
#SBATCH --job-name=build-pmlog
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_bpmlog_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_bpmlog_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif

apptainer exec \
  --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO" \
  "$SIF" \
  bash -c "
    PB=/opt/protobuf-29.0/install
    ABSL=/opt/abseil-cpp-20240722.0/install
    # Regenerate taskgraph.pb.{h,cc} with PACE's own protoc so gencode always
    # matches the runtime headers we compile/link against (the checked-in
    # pre-generated files were built with a different protoc and failed with
    # 'Protobuf C++ gencode is built with an incompatible version').
    \$PB/bin/protoc --cpp_out=$REPO/src/clos --proto_path=$REPO/src/clos $REPO/src/clos/taskgraph.proto
    ABSL_LIBS=\$(ls \$ABSL/lib/libabsl_*.a | sed -e 's#.*/lib#-l#' -e 's#\.a\$##' | tr '\n' ' ')
    PBFLAGS=\"-I\$PB/include -I\$ABSL/include\"
    PBLIBS=\"-L\$PB/lib -Wl,-rpath,\$PB/lib -L\$ABSL/lib -lprotobuf -lutf8_validity -lutf8_range -Wl,--start-group \$ABSL_LIBS -Wl,--end-group\"
    FF_HOME=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow
    echo \"PBFLAGS=\$PBFLAGS\"
    echo \"PBLIBS=\$PBLIBS\"
    cd $REPO/src/clos
    make -j8 PBFLAGS=\"\$PBFLAGS\" FF_HOME=\"\$FF_HOME\"
    cd $REPO/src/clos/datacenter
    make -j8 htsim_tcp_glassfb_pmlog FF_HOME=\"\$FF_HOME\" PBFLAGS=\"\$PBFLAGS\" PBLIBS=\"\$PBLIBS\" CFLAGS=\"-Wall -std=c++17 -O3 -no-pie -fuse-ld=gold\"
    echo 'Done ->' \$(ls $REPO/src/clos/datacenter/htsim_tcp_* 2>&1)
  "
