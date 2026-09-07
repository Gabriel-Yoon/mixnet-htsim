#!/bin/bash
# Submit a paper_ref job: link gate, then run a FROZEN COPY of the scripts tree.
#
#   scripts/submit_paper_job.sh mb.sbatch
#
# TWO GUARDS, each for a failure that has already happened here.
#
# 1. LINK GATE. Twice the tree reached a state where targets were unbuildable
#    while their binaries kept producing results (a dynamic_cast typeinfo
#    dependency in ffapp.o; then a duplicate check_non_null across eleven
#    translation units), and once a rebuild reported COMPLETED in 14 seconds and
#    changed nothing because $(OBJS) was linked but never declared. linkcheck
#    links every target into a scratch OUTDIR -- never over a binary a running
#    job is executing, which is how an earlier mid-sweep rebuild invalidated two
#    cells. Link errors are fatal; staleness warns (STRICT_STALE=1 to harden).
#
# 2. FROZEN SCRIPTS. Editing portmap_cliff.sh while a job was executing it made
#    that job re-run four cells: ~2.8 hours of duplicated compute and four
#    duplicate CSV rows. The edit preserved the file length, which I had reasoned
#    made it safe. It does not: the rewrite is truncate-then-write, and bash
#    reads a running script incrementally by byte offset, so it can resume at an
#    offset that no longer means what it did when it was recorded. Nothing errors.
#
#    So the job stops reading the working tree once it starts. The whole scripts
#    directory is copied into a per-job snapshot, absolute references inside the
#    copies are repointed at the snapshot, and the job runs the snapshot. Editing
#    a script is then safe by construction rather than by remembering -- and the
#    snapshot IS the code that ran, kept beside the commit it came from.
#
#    One gap, stated rather than papered over. Three lines are not repointed,
#    all of the form $ROOT/scripts/gen_weightmatrix.py, in ep128_domain_test.sh,
#    htsim_mixnet_baselines.sh and htsim_nvl72_crossover.sh. $ROOT is not
#    expanded at copy time, and in those three it does not name this repo at all
#    -- it is a stale mixnet-sim path, two of them macOS paths that do not exist
#    on this cluster. So the calls are already dead here (each is guarded by
#    [ -s \"$WM\" ] ||, so they fire only if the weightmatrix is missing) and none
#    is on a paper-row path. Repointing them at the snapshot would make them
#    start working, which is a behaviour change and not this script's business.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

[ $# -ge 1 ] || { echo "usage: $0 <sbatch-file> [sbatch args...]" >&2; exit 2; }
JOB=$1; shift
[ -f "$JOB" ] || { echo "no such sbatch file: $JOB" >&2; exit 2; }

# ---- 1. link gate -----------------------------------------------------------
if [ "${SKIP_LINK_GATE:-0}" = "1" ]; then
  echo "link gate: SKIPPED (SKIP_LINK_GATE=1) -- say so in the row's note"
else
  echo "link gate: linking every target into a scratch dir (production untouched)..."
  if ! sbatch --wait "$REPO/linkcheck.sbatch" > /dev/null 2>&1; then
    echo "link gate: FAIL -- not submitting $JOB" >&2
    tail -25 "$REPO"/slurm_linkcheck_*.err 2>/dev/null \
      | grep -iE "error:|undefined reference|multiple definition" | head -12 >&2
    echo "  fix the build, or set SKIP_LINK_GATE=1 to submit anyway (and say so in the row's note)" >&2
    exit 1
  fi
  echo "link gate: PASS"
fi

# ---- 1b. does this build carry the link-rate fix? ---------------------------
# Queue::Queue used to truncate picoseconds-per-byte to an integer, so a link ran
# at its stated rate only when the rate divided 1000 GB/s -- glass's electrical
# tier at 1800 truncated to ZERO and had no transmission time at all. Rows from
# such a binary are refused by gate_quotable unless they carry
# link_rate_fixed=yes, and this is what sets it.
#
# Two conditions, and it fails safe: the source must carry the exact-integer
# drainTime, AND the production binary must be newer than the object it links
# (otherwise the fix is in the tree but not in the binary -- the stale-binary
# defect this project has already hit). Either unmet leaves the flag empty and
# the rows come out unquotable, which is a missing point rather than a wrong one.
LINK_RATE_FIXED=""
if grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null; then
  _bin="$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm"
  _obj="$REPO/src/clos/queue.o"
  if [ -f "$_bin" ] && [ -f "$_obj" ] && [ "$_bin" -nt "$_obj" ]; then
    LINK_RATE_FIXED=yes
  else
    echo "link-rate fix: in the source but the binary is older than queue.o --" \
         "rows will be marked unquotable until a rebuild" >&2
  fi
fi
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "link_rate_fixed=${LINK_RATE_FIXED:-<no>}  binary_sha=$HTSIM_BINARY_SHA"

# ---- 2. freeze the scripts tree ---------------------------------------------
SNAP="$REPO/jobsnaps/$(date +%Y%m%d_%H%M%S)_$(basename "$JOB" .sbatch)_$$"
mkdir -p "$SNAP" || { echo "cannot create snapshot dir $SNAP" >&2; exit 1; }
cp -R "$REPO/scripts" "$SNAP/scripts" || { echo "snapshot copy failed" >&2; exit 1; }
cp "$JOB" "$SNAP/job.sbatch"

# Repoint references inside the copies at the snapshot:
#   absolute  $REPO/scripts/x      -> $SNAP/scripts/x   (source lines, py calls)
#   bare word  scripts/x           -> $SNAP/scripts/x   (relative, cwd-resolved)
# A bare-word rewrite that hits a string rather than a path is harmless: the
# snapshot is byte-identical to the tree at this instant, so it names the same
# content either way.
for f in "$SNAP/job.sbatch" "$SNAP"/scripts/*.sh; do
  [ -f "$f" ] || continue
  sed -i -e "s#$REPO/scripts/#$SNAP/scripts/#g" \
         -e "s#\(^\|[[:space:]]\)scripts/#\1$SNAP/scripts/#g" "$f"
done
chmod +x "$SNAP"/scripts/*.sh 2>/dev/null

RUNNER=$(grep -oE "$SNAP/scripts/[A-Za-z0-9_]+\.sh" "$SNAP/job.sbatch" | head -1)

{
  echo "snapshot   $(date -Is)"
  echo "sbatch     $JOB"
  echo "runner     ${RUNNER:-<inline bash -c, no runner file>}"
  echo "commit     $(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "tree       $(git diff --quiet 2>/dev/null && echo clean || echo DIRTY-uncommitted-changes-present)"
  echo "files      $(ls -1 "$SNAP/scripts" | wc -l) copied from $REPO/scripts"
} > "$SNAP/PROVENANCE.txt"

echo "frozen scripts: $SNAP"
grep -E "^(commit|tree|runner) " "$SNAP/PROVENANCE.txt" | sed "s/^/  /"
exec sbatch --export=ALL "$SNAP/job.sbatch" "$@"
