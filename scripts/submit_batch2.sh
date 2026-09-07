#!/bin/bash
# The deferred batches, each rung its own job, on the fixed binary.
#
# DRY_RUN=1 prints what would go and submits nothing. That flag exists because
# earlier today I ran a submitter as a "check the guard refuses" test at a moment
# when the guard correctly passed, and it submitted a second full set: 36 rung
# files ended up written by two jobs each.
#
# Batches here:
#   drop   glass drop cells for every quoted glass row so far. The glass rungs ran
#          on _glassfb_pm, which has no counter, so those rows read "not measured".
#          Pre-fix, glass EP=32 dropped 208 packets at its quoted row DESPITE zero
#          timeouts; that has to be re-established, not carried over.
#   s1128  nvl64_pkt_s1 at EP=128 Arctic, the striping upper bound at the scale
#          where the pinned incumbent is furthest behind.
#   s1mb   nvl64_pkt_s1 EP=16 at mb 4/16/32, so R6's microbatch contrast has the
#          striped end of the bracket and not only the pinned one.
#
# Microbatch is a property of the WORKLOAD FILE, not a flag. Passing the mb8 file
# for every mb ran the same simulation four times and labelled the rows 4/8/16/32.
# The fbuf name is derived from $mb here for that reason.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"
RESULTS=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results

SNAP=$REPO/jobsnaps/batch2_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"
cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"

LINK_RATE_FIXED=""
if grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null; then
  if [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" -nt "$REPO/src/clos/queue.o" ]; then
    LINK_RATE_FIXED=yes
  fi
fi
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
if [ "$LINK_RATE_FIXED" != yes ]; then
  echo "REFUSING: binary does not carry the link-rate fix; rows would be unquotable" >&2
  exit 1
fi
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"
echo "frozen runner: $RUN"

N=0
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  if [ -n "${ONLY:-}" ]; then
    case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N + 1)); printf "  WOULD SUBMIT %-30s\n" "$tag"; return 0
  fi
  local id
  id=$(sbatch --parsable --export=ALL -J "b2_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b2_${tag}_%j.out" -e "$REPO/slurm_b2_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N + 1))
  printf "  %-30s %s\n" "$tag" "$id"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

echo "### (7) glass drop cells at the quoted rungs"
for mb in 4 8 16 32; do
  fb=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  [ -f "$RESULTS/$fb" ] || { echo "  SKIP mb=$mb: $fb missing" >&2; continue; }
  sub 8G 3:00:00 "gd16m${mb}_q532" glassdrop 16 128 "$fb" wm_ep16.txt ep16_0_8_4.txt 532 "$mb" "gd16m${mb}_q532"
done
sub 12G 4:00:00 "gd32_q2133" glassdrop 32 256 "$L32" wm_ep32.txt ep32_gt.txt 2133 8 "gd32_q2133"
sub 20G 8:00:00 "gd64_q17067" glassdrop 64 512 "$QME" wm_ep64.txt ep64_gt.txt 17067 8 "gd64_q17067"

echo "### (3) nvl64_pkt_s1 EP=128 Arctic, all six rungs"
for q in 600 1200 2400 4800 9600 19200; do
  sub 40G 20:00:00 "s1_128_q$q" pkt nvl64_pkt_s1 128 1024 "$ARC" wm_ep128.txt 64 1 900 100 "$q" 540 "s1_128_q$q"
done

echo "### (2) nvl64_pkt_s1 EP=16 microbatch 4/16/32"
for mb in 4 16 32; do
  fb=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  [ -f "$RESULTS/$fb" ] || { echo "  SKIP mb=$mb: $fb missing" >&2; continue; }
  for q in 600 1200 2400 4800 9600 19200; do
    sub 16G 6:00:00 "s1m${mb}_q$q" pkt nvl64_pkt_s1 16 128 "$fb" wm_ep16.txt 64 1 900 100 "$q" 540 "s1m${mb}_q$q"
  done
done

echo
echo "submitted $N job(s)"
