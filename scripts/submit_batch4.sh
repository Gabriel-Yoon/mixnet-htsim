#!/bin/bash
# Batch 4: the two EP=128 gaps.
#
# hgx8_pkt EP=128 post-fix. pkt128vt was cancelled pre-fix to free the binaries
# for the rebuild, and neither batch 2 nor 3 resubmitted it, so Fig 6c's HGX-8 bar
# would be the only pre-fix number left on the page. Three rungs at 16x/31x/62x of
# its port BDP, on the drop build so the row can be quoted through the drop-aware
# branch if its timeouts turn out to be the buffer-invariant kind again.
#
# Its EP=32 and EP=64 rows were IDENTICAL post-fix (145.497 / 164.522 / 144.519),
# because that fabric is bounded by the NIC tier at 100 GB/s and the +11% on its
# NVLink tier never reaches the makespan. So 365.733 is the expectation here too --
# but an expectation is not a measurement, and the row cannot be quoted on one.
#
# nvl64_pkt EP=128 tail at the quoted q=2176. Its makespan stands (L=50 was exact
# under both arithmetics), but its FCT tail was lost: the walk shared one output
# directory across rungs and the hgx8 sweep overwrote it before it could be read.
# This re-runs that single cell for the tail alone; the makespan must reproduce
# 247.218 or the tail belongs to some other run.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch4_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"

LINK_RATE_FIXED=""
grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null &&
  [ "$REPO/src/clos/datacenter/htsim_tcp_nvswitch_drop" -nt "$REPO/src/clos/queue.o" ] &&
  LINK_RATE_FIXED=yes
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
[ "$LINK_RATE_FIXED" = yes ] || { echo "REFUSING: binary lacks the link-rate fix" >&2; exit 1; }
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"

N=0
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  if [ "${DRY_RUN:-0}" = 1 ]; then N=$((N+1)); printf "  WOULD SUBMIT %-22s\n" "$tag"; return 0; fi
  local id
  id=$(sbatch --parsable --export=ALL -J "b4_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b4_${tag}_%j.out" -e "$REPO/slurm_b4_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-22s %s\n" "$tag" "$id"
}

ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

echo "### hgx8_pkt EP=128, drop build, three rungs"
for q in 1224 2448 4896; do
  sub 40G 20:00:00 "h128_q$q" pkt hgx8_pkt 128 1024 "$ARC" wm_ep128.txt 8 4 112.5 50 "$q" 270 "h128_q$q"
done

echo "### nvl64_pkt EP=128 tail at the quoted q=2176"
sub 40G 20:00:00 "n128_q2176" pkt nvl64_pkt 128 1024 "$ARC" wm_ep128.txt 64 18 50 100 2176 540 "n128_q2176"

echo
echo "submitted $N job(s)"
