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

# Build gate for paper_ref jobs. Two questions, both of which have bitten:
#
#   1. Does every target still LINK?  Twice the tree reached a state where
#      targets were unbuildable while their binaries kept producing results --
#      first a dynamic_cast typeinfo dependency in ffapp.o, then a duplicate
#      check_non_null across eleven translation units.
#
#   2. Is any production binary STALE?  The link rules linked $(OBJS) without
#      declaring them, so make would not relink an existing target when a shared
#      source changed: six queue classes edited, objects rebuilt, binary
#      untouched, build "COMPLETED" in 14 seconds.
#
# `make all` would answer both by overwriting the binaries running jobs are
# executing -- how a mid-sweep make clean destroyed a binary here. $(OUTDIR)
# sends every -o into a scratch directory instead.
#
# The staleness test is mtime, not hash: a binary older than an object it links
# is unambiguously stale, whereas two links of identical sources need not be
# byte-identical (build ids, paths), so a hash difference alone would cry wolf.
# The hash comparison is still reported, as information rather than a verdict.

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
    echo \"LINK GATE PASS: \$(ls \$LC | grep -c '^htsim_') targets linked\"

    # Staleness: a production binary older than anything it links is stale.
    NEWEST_OBJ=\$(ls -t ../*.o ../libhtsim.a *.o 2>/dev/null | head -1)
    STALE=0
    for b in \$(ls \$LC | grep '^htsim_'); do
      [ -f \"\$b\" ] || { echo \"  absent in production: \$b\"; continue; }
      if [ \"\$b\" -ot \"\$NEWEST_OBJ\" ]; then
        echo \"  STALE: \$b is older than \$NEWEST_OBJ -- it links objects newer than itself\"
        STALE=\$((STALE+1))
      fi
      if ! cmp -s \"\$b\" \"\$LC/\$b\"; then
        echo \"  differs from a fresh link (informational): \$b\"
      fi
    done
    if [ \$STALE -gt 0 ]; then
      echo \"STALENESS WARNING: \$STALE binar(ies) predate the objects they link.\"
      echo '  Staleness is reported, not fatal: a library change is often behaviour-neutral'
      echo '  (an env-gated log, a flag-gated path, an extra output column, a counter), and'
      echo '  hard-failing on it would block every submission for changes that cannot move a'
      echo '  number. Check the diff before quoting a row from a listed binary; set'
      echo '  STRICT_STALE=1 to make this fatal.'
      if [ \"\${STRICT_STALE:-0}\" = '1' ]; then rm -rf \$LC; exit 1; fi
    else
      echo 'STALENESS CHECK PASS: no production binary predates the objects it links'
    fi
    rm -rf \$LC
  "
