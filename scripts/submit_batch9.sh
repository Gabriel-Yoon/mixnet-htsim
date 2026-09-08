#!/bin/bash
# Batch 9: 200G/lane becomes the design point -- the microbatch sweep and the drop cells.
#
# (1) EP=16 at mb 4 / 16 / 32. mb 8 is already g16b800 (87.700 at q=533), so only the
# other three walks are missing; asking for all four would have re-run a cell that
# exists and the guard would refuse it anyway.
#
# (2) A drop cell on each of the four quoted 800 rows, by the standing rule. Each
# must reproduce its plain twin's makespan or collect_rungs refuses the merge:
#
#   g16b800  q=533     87.700     g64b800  q=8533    39.879
#   g32b800  q=2133    75.253     g128b800 q=34133  194.609
#
# The EP=128 cell is the one that matters most: that walk's 400 GB/s counterpart has
# 66 M measured drops at its best rung and no clean rung at all, so "0 timeouts AND 0
# drops at 64x" is the claim the whole promotion rests on, and it should be measured
# on the counter build rather than inferred from the plain one.
#
# Ladders are EP=16's own BDP multiples doubled, as batch 8: 0.5x..16x of the
# 800 GB/s BDP. All four mb walks share the declared ("glassfb_800","16") ladder,
# which is what submitted_q keys on.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch9_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"

LINK_RATE_FIXED=""
grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null &&
  [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" -nt "$REPO/src/clos/queue.o" ] &&
  [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_drop" -nt "$REPO/src/clos/queue.o" ] &&
  LINK_RATE_FIXED=yes
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
[ "$LINK_RATE_FIXED" = yes ] || { echo "REFUSING: a binary lacks the link-rate fix" >&2; exit 1; }
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b9_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
  return 0
}

N=0
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  guard "$tag" || return 0
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N+1)); printf "  WOULD SUBMIT  %-18s mem=%-5s t=%-9s  %s\n" "$tag" "$mem" "$tm" "$*"; return 0
  fi
  local id
  id=$(sbatch --parsable --export=ALL -J "b9_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b9_${tag}_%j.out" -e "$REPO/slurm_b9_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-24s %s\n" "$tag" "$id"
}

ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

export RUNG_PORT_BW=800 RUNG_SYS=glassfb_800

echo "### (1) EP=16 microbatch sweep at 200G/lane (mb 8 already exists as g16b800)"
for mb in 4 16 32; do
  FB=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  [ -f "/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results/$FB" ] || {
    echo "REFUSING mb=$mb: $FB does not exist" >&2; continue; }
  for q in 266 533 1066 2133 4267 8533; do
    sub 8G 4:00:00 "g16b800m${mb}_q$q" glass 16 128 "$FB" wm_ep16.txt ep16_0_8_4.txt "$q" "$mb" "g16b800m${mb}_q$q"
  done
done

echo "### (2) drop cells on the four quoted 800 rows"
sub 8G  4:00:00  "gd16b800_q533"    glassdrop 16  128  llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf wm_ep16.txt ep16_0_8_4.txt 533   8 "gd16b800_q533"
sub 20G 8:00:00  "gd32b800_q2133"   glassdrop 32  256  "$L32" wm_ep32.txt ep32_gt.txt   2133  8 "gd32b800_q2133"
sub 20G 8:00:00  "gd64b800_q8533"   glassdrop 64  512  "$QME" wm_ep64.txt ep64_gt.txt   8533  8 "gd64b800_q8533"
sub 40G 20:00:00 "gd128b800_q34133" glassdrop 128 1024 "$ARC" wm_ep128.txt ep128_gt.txt 34133 8 "gd128b800_q34133"

unset RUNG_PORT_BW RUNG_SYS
echo
echo "submitted/listed $N job(s)"
