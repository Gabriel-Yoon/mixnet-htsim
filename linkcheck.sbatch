#!/bin/bash
#SBATCH --job-name=linkcheck
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_linkcheck_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_linkcheck_%j.err

# Build gate for paper_ref jobs: prove every target still LINKS, without
# relinking any of them.
#
# Two link-rule defects reached the tree in one session and both were found by a
# build happening to fail rather than by anything checking:
#   - the hierarchical A2A's dynamic_cast put a typeinfo dependency into ffapp.o,
#     leaving twelve targets unbuildable while their binaries kept working;
#   - the fix for that paired glassfb_topology.o with flat_topology.o and hit a
#     latent duplicate definition of check_non_null present in eleven files.
# Each time the binaries on disk had stopped being reproducible from the
# committed source, which is provenance sub-class D.
#
# `make all` would rewrite the binaries running jobs are executing -- how a
# mid-sweep `make clean` destroyed a binary and invalidated two cells earlier in
# this project. $(OUTDIR) sends every -o into a scratch directory instead, so
# this proves the rules work and touches nothing.

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
    set -uo pipefail
    LC=\$(mktemp -d /tmp/linkcheck.XXXXXX)
    PB=/opt/protobuf-29.0/install
    ABSL=/opt/abseil-cpp-20240722.0/install
    ABSL_LIBS=\$(ls \$ABSL/lib/libabsl_*.a | sed -e 's#.*/lib#-l#' -e 's#\.a\$##' | tr '\n' ' ')
    PBFLAGS=\"-I\$PB/include -I\$ABSL/include\"
    PBLIBS=\"-L\$PB/lib -Wl,-rpath,\$PB/lib -L\$ABSL/lib -lprotobuf -lutf8_validity -lutf8_range -Wl,--start-group \$ABSL_LIBS -Wl,--end-group\"
    FF_HOME=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow
    cd $REPO/src/clos
    make -j8 PBFLAGS=\"\$PBFLAGS\" FF_HOME=\"\$FF_HOME\" > \$LC/lib.log 2>&1
    if [ \$? -ne 0 ]; then
      echo 'LINK GATE FAIL (library)'
      grep -iE 'error:' \$LC/lib.log | head -8
      exit 1
    fi
    cd $REPO/src/clos/datacenter
    make -j8 all OUTDIR=\"\$LC/\" FF_HOME=\"\$FF_HOME\" PBFLAGS=\"\$PBFLAGS\" PBLIBS=\"\$PBLIBS\" CFLAGS='-Wall -std=c++17 -O3 -no-pie -fuse-ld=gold' > \$LC/build.log 2>&1
    if [ \$? -ne 0 ]; then
      echo 'LINK GATE FAIL (targets)'
      grep -iE 'error:|undefined reference|multiple definition' \$LC/build.log | head -12
      exit 1
    fi
    echo \"LINK GATE PASS: \$(ls \$LC | grep -c '^htsim_') targets linked into \$LC\"
    rm -rf \$LC
  "
