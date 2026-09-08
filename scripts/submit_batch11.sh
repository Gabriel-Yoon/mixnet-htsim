#!/bin/bash
# Batch 11: HGX-8 at EP=16, microbatch 4 / 16 / 32.
#
# Completes the load panel. glassfb_800 and nvl64_pkt_s1 already have all four
# microbatches at EP=16; hgx8_pkt has only mb=8, so the third fabric is a single
# point on a figure whose whole subject is the trend against load.
#
# EP=64 WAS ASKED FOR AND IS NOT HERE. The qwenMoE EP=64 graphs exist at mb=8
# only -- the axes that vary in that set are L, seq and tp, never microbatch --
# and the task graphs have no producer in this repo (sub-class B in
# methods_provenance.md: committed .fbuf inputs, no generator, no recorded
# command). EP=32 was then proposed as the cheap substitute and it is not
# available either: llamaMoE at EP=32 exists at mb=8 alone. So the load figure
# stays a single EP=16 panel, and that is a fact about the inputs, not a choice.
#
# Everything else follows the existing hgx8_pkt walks exactly -- same drop build,
# same D/S/L/nic (8 / 4 / 112.5 / 50), same six-rung ladder, same 270 qc -- so a
# new mb row is comparable to the mb=8 row already quoted. Tags are h16m<mb>_q<q>,
# which collect_rungs.py already parses: mb_from_tag reads the m<digits> and the
# ("hgx8_pkt","16") ladder is declared, so the gap check works from rung one.
#
# The drop-counter cells are NOT submitted here. Which rung is quoted is not known
# until the ladder lands, and submitting a drop cell for every rung would double
# the job count to measure loss on five rungs nobody quotes.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch11_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"
{ echo "snapshot $(date -Is)"; echo "commit   $(git rev-parse HEAD)"
  echo "tree     $(git diff --quiet && echo clean || echo DIRTY)"; } > "$SNAP/PROVENANCE.txt"

LINK_RATE_FIXED=""
grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null &&
  [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" -nt "$REPO/src/clos/queue.o" ] &&
  LINK_RATE_FIXED=yes
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
[ "$LINK_RATE_FIXED" = yes ] || { echo "REFUSING: binary lacks the link-rate fix" >&2; exit 1; }
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"

# The pkt walks run the drop-instrumented NVSwitch build, and it is NOT the binary
# that was rebuilt today -- it is the same one that produced the existing h16
# mb=8 row, which is what makes the new microbatches comparable to it.
BIN=$REPO/src/clos/datacenter/htsim_tcp_nvswitch_drop
[ -x "$BIN" ] || { echo "REFUSING: $BIN missing" >&2; exit 1; }
echo "pkt binary: $(ls -la "$BIN" | awk '{print $5, $6, $7, $8}')  md5=$(md5sum "$BIN" | cut -c1-12)"

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b11_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
  return 0
}

N=0
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  guard "$tag" || return 0
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N+1)); printf "  WOULD SUBMIT  %-20s mem=%-5s t=%s\n" "$tag" "$mem" "$tm"; return 0
  fi
  local id
  id=$(sbatch --parsable --export=ALL -J "b11_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b11_${tag}_%j.out" -e "$REPO/slurm_b11_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-22s %s\n" "$tag" "$id"
}

QS="306 612 1224 2448 4896 9792"
for spec in "4 16G" "16 16G" "32 24G"; do
  set -- $spec; mb=$1 mem=$2
  FB=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  if [ ! -f /storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results/$FB ]; then
    echo "  SKIP mb=$mb: $FB does not exist" >&2; continue
  fi
  echo "### hgx8_pkt EP=16 mb=$mb"
  for q in $QS; do
    sub "$mem" 6:00:00 "h16m${mb}_q$q" pkt hgx8_pkt 16 128 "$FB" wm_ep16.txt 8 4 112.5 50 "$q" 270 "h16m${mb}_q$q"
  done
done

echo
echo "submitted/listed $N job(s)"
