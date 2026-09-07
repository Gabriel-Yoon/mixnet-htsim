#!/bin/bash
# The calibration sweep: 8 message sizes x 2 variants x 6 buffers = 96 cells.
#
# The buffer ladder is in multiples of each variant's OWN port BDP, because the
# two variants have different port bandwidths (25 vs 450 GB/s) and therefore
# different BDPs. Quoting both against one ladder would compare them at different
# multiples of their own capacity, which is the thing the walk exists to avoid.
#
#   variant a  25 GB/s  -> 25 000 B per 1 us RTT -> 17 pkt at 1500 B
#   variant b  450      -> 450 000              -> 300 pkt
#
# Ladder 2x 4x 8x 16x 32x 64x of that, as everywhere else in the paper.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/calib_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/calib_cell.sh "$SNAP/"; chmod +x "$SNAP/calib_cell.sh"
RUN="$SNAP/calib_cell.sh"

export LINK_RATE_FIXED=yes
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" || {
  echo "REFUSING: source lacks the link-rate fix" >&2; exit 1; }
[ "$REPO/src/clos/datacenter/htsim_tcp_nvswitch_drop" -nt "$REPO/src/clos/queue.o" ] || {
  echo "REFUSING: the drop binary predates queue.o" >&2; exit 1; }
[ -x "$REPO/src/clos/gen_decode_block" ] || {
  echo "REFUSING: gen_decode_block is not built" >&2; exit 1; }
echo "binary_sha=$HTSIM_BINARY_SHA  runner=$RUN"

N=0
sub () { # mem time tag var M q
  local mem=$1 tm=$2 tag=$3 var=$4 M=$5 q=$6
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  if [ "${DRY_RUN:-0}" = 1 ]; then N=$((N+1)); printf "  WOULD SUBMIT %-26s var=%s M=%-9s q=%s\n" "$tag" "$var" "$M" "$q"; return 0; fi
  local id
  id=$(sbatch --parsable --export=ALL -J "cal_$tag" -A gts-syu334-ece -p cpu-small \
       -q inferno -N 1 -n 1 -c 4 --mem=12G -t "$tm" \
       -o "$REPO/slurm_cal_${tag}_%j.out" -e "$REPO/slurm_cal_${tag}_%j.err" \
       --wrap "bash $RUN $var $M $q $tag")
  N=$((N+1)); printf "  %-26s %s\n" "$tag" "$id"
}

for M in 8192 32768 131072 524288 2097152 8388608 33554432 67108864; do
  for var in a b; do
    case $var in a) bdp=17 ;; b) bdp=300 ;; esac
    for k in 2 4 8 16 32 64; do
      q=$((bdp * k))
      sub 12G 4:00:00 "cal${var}_M${M}_k${k}" "$var" "$M" "$q"
    done
  done
done

echo
echo "submitted $N cell(s)"
