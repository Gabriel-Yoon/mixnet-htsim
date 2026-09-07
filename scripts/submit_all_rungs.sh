#!/bin/bash
# Submit every rung of every walk as its own job, longest pole first.
#
# One frozen copy of rung.sh is made and every job runs THAT, so editing the
# runner afterwards cannot disturb a job in flight -- the same property
# submit_paper_job.sh gives, obtained once here rather than 170 times.
#
# Order is deliberate: EP=128 first. Its rungs are 2-3 hours and everything else
# is minutes, so the only way the day fails is the longest pole starting late.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/rungs_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"
cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"
{ echo "snapshot $(date -Is)"; echo "commit   $(git rev-parse HEAD)"
  echo "tree     $(git diff --quiet && echo clean || echo DIRTY)"; } > "$SNAP/PROVENANCE.txt"

# the fix flag every row must carry, computed once and exported to every job
LINK_RATE_FIXED=""
if grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null; then
  if [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" -nt "$REPO/src/clos/queue.o" ]; then
    LINK_RATE_FIXED=yes
  fi
fi
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
if [ "$LINK_RATE_FIXED" != yes ]; then
  echo "REFUSING: the binary does not carry the link-rate fix (or is older than queue.o)." >&2
  echo "  Every row would be unquotable. Rebuild first." >&2
  exit 1
fi
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"
echo "frozen runner: $RUN"
echo

N=0
# ONLY="tag tag ..." submits just those rungs -- used to re-run the ones a
# double submission corrupted, without touching the jobs already in flight.
# DRY_RUN=1 exercises the guards and prints what WOULD go, submitting nothing.
# Both exist because this script was once run as a "check the guard refuses" test
# at a moment when the guard correctly passed, and it submitted a second full set:
# 36 rung files ended up written by two jobs each.
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  local id
  if [ -n "${ONLY:-}" ]; then
    case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N + 1)); printf "  WOULD SUBMIT %-34s\n" "$tag"; return 0
  fi
  id=$(sbatch --parsable --export=ALL \
       -J "r_$tag" -A gts-syu334-ece -p cpu-medium -q inferno \
       -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_rung_${tag}_%j.out" -e "$REPO/slurm_rung_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N + 1))
  printf "  %-34s %s\n" "$tag" "$id"
}

# The workload directory. rung.sh has its own $R; this script needs its own,
# and referencing an undefined $R here aborted the mb loop under set -u.
RESULTS=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

echo "### glass EP=128 (longest pole, submitted first)"
for q in 533 1066 2133 4267 8533 17067; do
  sub 40G 20:00:00 "g128_q$q" glass 128 1024 "$ARC" wm_ep128.txt ep128_gt.txt "$q" 8 "g128_q$q"
done

echo "### glass EP=64"
for q in 533 1064 2133 4267 8533 17067; do
  sub 20G 8:00:00 "g64_q$q" glass 64 512 "$QME" wm_ep64.txt ep64_gt.txt "$q" 8 "g64_q$q"
done

echo "### glass EP=32"
for q in 266 533 1066 2133 4267 8533; do
  sub 12G 4:00:00 "g32_q$q" glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt "$q" 8 "g32_q$q"
done

echo "### glass EP=16, mb 4/8/16/32"
# The microbatch is a property of the WORKLOAD, not a flag: each mb is its own
# .fbuf. Passing the mb8 file for every mb ran the same simulation four times and
# labelled the rows 4/8/16/32 -- four identical points presented as a sweep. The
# fbuf name is derived from $mb here so that cannot recur.
for mb in 4 8 16 32; do
  fb=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  if [ ! -f "$RESULTS/$fb" ]; then
    echo "  SKIP mb=$mb: $fb does not exist" >&2; continue
  fi
  for q in 133 266 532 1064 2128 4256; do
    sub 8G 3:00:00 "g16m${mb}_q$q" glass 16 128 "$fb" wm_ep16.txt ep16_0_8_4.txt "$q" "$mb" "g16m${mb}_q$q"
  done
done

echo "### hgx8_pkt EP 16/32/64 (drop build)"
for spec in "16 128 $L16 wm_ep16.txt" "32 256 $L32 wm_ep32.txt" "64 512 $QME wm_ep64.txt"; do
  set -- $spec; ep=$1 nodes=$2 fb=$3 wm=$4
  for q in 306 612 1224 2448 4896 9792; do
    sub 16G 6:00:00 "h${ep}_q$q" pkt hgx8_pkt "$ep" "$nodes" "$fb" "$wm" 8 4 112.5 50 "$q" 270 "h${ep}_q$q"
  done
done

echo "### nvl64_pkt_s1 EP 16/32/64 (striping control)"
for spec in "16 128 $L16 wm_ep16.txt" "32 256 $L32 wm_ep32.txt" "64 512 $QME wm_ep64.txt"; do
  set -- $spec; ep=$1 nodes=$2 fb=$3 wm=$4
  for q in 600 1200 2400 4800 9600 19200; do
    sub 16G 6:00:00 "s1_${ep}_q$q" pkt nvl64_pkt_s1 "$ep" "$nodes" "$fb" "$wm" 64 1 900 100 "$q" 540 "s1_${ep}_q$q"
  done
done

echo
echo "submitted $N jobs"
echo "collect with: python3 scripts/collect_rungs.py"
