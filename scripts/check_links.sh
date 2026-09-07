#!/bin/bash
# Build gate: prove every target still links, without relinking any of them.
#
# WHY NOT `make all`. That would rewrite the binaries running jobs are executing
# -- the same hazard as the make clean that destroyed a binary mid-sweep. The
# Makefile's link outputs are prefixed with $(OUTDIR), so this links the full
# target list into a scratch directory and production is never touched.
#
# WHY IT EXISTS. Two link-rule defects reached the tree this session and both
# were found by a build happening to fail, not by anything checking:
#   - the hierarchical A2A's dynamic_cast put a typeinfo dependency in ffapp.o,
#     leaving twelve targets unbuildable while their binaries kept working;
#   - the fix for that paired glassfb_topology.o with flat_topology.o and hit a
#     latent duplicate definition of check_non_null in eleven files.
# In both cases the binaries on disk had stopped being reproducible from the
# committed source. That is provenance sub-class D, and this is its guard.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
LC=$(mktemp -d /tmp/linkcheck.XXXXXX)
trap 'rm -rf "$LC"' EXIT

PB=/opt/protobuf-29.0/install
ABSL=/opt/abseil-cpp-20240722.0/install
FF_HOME=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow

echo "link gate: building every target into $LC (production binaries untouched)"
ABSL_LIBS=$(ls $ABSL/lib/libabsl_*.a 2>/dev/null | sed -e 's#.*/lib#-l#' -e 's#\.a$##' | tr '\n' ' ')
PBFLAGS="-I$PB/include -I$ABSL/include"
PBLIBS="-L$PB/lib -Wl,-rpath,$PB/lib -L$ABSL/lib -lprotobuf -lutf8_validity -lutf8_range -Wl,--start-group $ABSL_LIBS -Wl,--end-group"

if make -j8 all OUTDIR="$LC/" FF_HOME="$FF_HOME" PBFLAGS="$PBFLAGS" PBLIBS="$PBLIBS" \
     CFLAGS="-Wall -std=c++17 -O3 -no-pie -fuse-ld=gold" > "$LC/build.log" 2>&1; then
  echo "link gate: PASS -- $(ls "$LC" | grep -c '^htsim_') target(s) linked"
  exit 0
fi
echo "link gate: FAIL" >&2
grep -iE "error:|undefined reference|multiple definition" "$LC/build.log" | head -12 >&2
echo "  (full log was $LC/build.log; it is removed on exit -- rerun to inspect)" >&2
exit 1
