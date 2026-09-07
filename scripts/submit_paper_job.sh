#!/bin/bash
# Submit a paper_ref job only if every target still links.
#
#   scripts/submit_paper_job.sh mb.sbatch
#
# WHY. Two link-rule defects reached the tree in one session, and both were found
# by a build happening to fail rather than by anything checking:
#   - the hierarchical A2A's dynamic_cast put a typeinfo dependency into ffapp.o,
#     leaving twelve targets unbuildable while their binaries kept working;
#   - the fix for that paired glassfb_topology.o with flat_topology.o and hit a
#     latent duplicate definition of check_non_null present in eleven files.
# Each time, the binaries on disk had quietly stopped being reproducible from the
# committed source -- provenance sub-class D. This is its guard.
#
# WHY NOT `make all`. That relinks the binaries running jobs are executing, which
# is how a mid-sweep make clean destroyed a binary and invalidated two cells
# earlier in this project. The gate links into a scratch OUTDIR instead, so it
# proves the rules work and touches nothing.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

[ $# -ge 1 ] || { echo "usage: $0 <sbatch-file> [sbatch args...]" >&2; exit 2; }
JOB=$1; shift
[ -f "$JOB" ] || { echo "no such sbatch file: $JOB" >&2; exit 2; }

if [ "${SKIP_LINK_GATE:-0}" = "1" ]; then
  echo "link gate: SKIPPED (SKIP_LINK_GATE=1) -- submitting unguarded"
else
  echo "link gate: linking every target into a scratch dir (production untouched)..."
  if ! sbatch --wait "$REPO/linkcheck.sbatch" > /dev/null 2>&1; then
    echo "link gate: FAIL -- not submitting $JOB" >&2
    tail -25 "$REPO"/slurm_linkcheck_*.err 2>/dev/null | grep -iE "error:|undefined reference|multiple definition" | head -12 >&2
    echo "  fix the build, or set SKIP_LINK_GATE=1 to submit anyway (and say so in the row's note)" >&2
    exit 1
  fi
  echo "link gate: PASS"
fi
exec sbatch "$JOB" "$@"
