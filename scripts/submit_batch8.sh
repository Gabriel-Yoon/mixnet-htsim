#!/bin/bash
# Batch 8: the 200G/lane line at EP=16 and EP=32, completing it from 16 to 128.
#
# LADDER CHOICE. "Same knobs as g64b800" is right for the knobs and wrong for the
# rungs. g64b800 used 2x..64x of the 800 GB/s BDP because that is the range EP=64's
# own 400 GB/s walk used; EP=16's walk runs 0.5x..16x and EP=32's runs 1x..32x, and
# those ranges were chosen so each walk brackets its own vanishing point. Reusing
# EP=64's range at EP=16 would start ABOVE where EP=16 already goes clean, and a
# walk whose first rung is already timeout-free cannot show that it is the first.
#
# So each EP keeps ITS OWN BDP multiples, doubled in packets because the 800 GB/s
# BDP is twice the 400 GB/s one (533.3 vs 266.7 pkt at MTU 1500, RTT 4x250 ns):
#
#   EP=16   0.5x 1x 2x 4x 8x 16x   ->   266  533 1066 2133 4267  8533
#   EP=32     1x 2x 4x 8x 16x 32x  ->   533 1066 2133 4267 8533 17067
#
# which makes each 800 rung comparable to the 400 rung at the SAME BDP multiple,
# rather than at the same absolute buffer. Worth stating because the two readings
# differ and the sentence has to pick one.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch8_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"

LINK_RATE_FIXED=""
grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null &&
  [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" -nt "$REPO/src/clos/queue.o" ] &&
  LINK_RATE_FIXED=yes
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
[ "$LINK_RATE_FIXED" = yes ] || { echo "REFUSING: binary lacks the link-rate fix" >&2; exit 1; }
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b8_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
  return 0
}

N=0
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  guard "$tag" || return 0
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N+1)); printf "  WOULD SUBMIT  %-16s mem=%-5s t=%-9s  %s\n" "$tag" "$mem" "$tm" "$*"; return 0
  fi
  local id
  id=$(sbatch --parsable --export=ALL -J "b8_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b8_${tag}_%j.out" -e "$REPO/slurm_b8_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-22s %s\n" "$tag" "$id"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

# Everything except the port rate is the design point's: same maps, same tp=1 ep=1
# (both graphs are dp2 tp1 pp4, so the topology's defaults are correct for them).
export RUNG_PORT_BW=800 RUNG_SYS=glassfb_800

echo "### EP=16 at 200G/lane, 0.5x..16x of the 800 GB/s BDP"
for q in 266 533 1066 2133 4267 8533; do
  sub 8G 4:00:00 "g16b800_q$q" glass 16 128 "$L16" wm_ep16.txt ep16_0_8_4.txt "$q" 8 "g16b800_q$q"
done

echo "### EP=32 at 200G/lane, 1x..32x"
for q in 533 1066 2133 4267 8533 17067; do
  sub 20G 8:00:00 "g32b800_q$q" glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt "$q" 8 "g32b800_q$q"
done
unset RUNG_PORT_BW RUNG_SYS

echo
echo "submitted/listed $N job(s)"
