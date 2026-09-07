#!/bin/bash
# Batch 6: the placement ablation, on the fixed binary.
#
# The paper quotes naive rank order 221.5 ms against EP-aware placement 195.2 ms at
# EP=16, a 13.5% gain. Both are PRE-FIX numbers and it is the last such pair the
# paper still quotes.
#
# READ THIS BEFORE PAIRING THE RESULT WITH ANYTHING. Re-running only the
# placement-OFF arm does not refresh that sentence. The post-fix EP=16 quoted row is
# 87.613 ms, not 195.2 -- the two differ by more than the ablation does, because the
# paper's pair came from an older configuration as well as an older binary. A new
# off-number set against the old on-number would be a comparison across two changes
# at once, which is the shape of every mistake this pipeline has made. The gain has
# to be quoted as (this off-arm) against (the current 87.613 on-arm), both post-fix,
# or not quoted.
#
# Three rungs per EP, bracketing and including the quoted buffer, because placement
# off will not be timeout-free where placement on is and the walk needs somewhere to
# vanish. Keyed npl* so plot_paper's headline reduction excludes them exactly as it
# excludes the skew and hierarchical cells: they share (system, ep, mb) with the
# plain walk and would otherwise compete to be its drawn point.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch6_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"

LINK_RATE_FIXED=""
grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null &&
  [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" -nt "$REPO/src/clos/queue.o" ] &&
  LINK_RATE_FIXED=yes
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
[ "$LINK_RATE_FIXED" = yes ] || { echo "REFUSING: htsim_tcp_glassfb_pm lacks the link-rate fix" >&2; exit 1; }
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b6_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
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
  id=$(sbatch --parsable --export=ALL -J "b6_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b6_${tag}_%j.out" -e "$REPO/slurm_b6_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-22s %s\n" "$tag" "$id"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

export RUNG_EP_PLACE=0

echo "### EP=16 placement OFF, against the quoted 87.613 at q=532"
for q in 266 532 1064; do
  sub 8G 4:00:00 "npl16_q$q" glass 16 128 "$L16" wm_ep16.txt ep16_0_8_4.txt "$q" 8 "npl16_q$q"
done

echo "### EP=32 placement OFF, against the quoted 77.918 at q=2133"
for q in 1066 2133 4267; do
  sub 20G 8:00:00 "npl32_q$q" glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt "$q" 8 "npl32_q$q"
done

unset RUNG_EP_PLACE
echo
echo "submitted/listed $N job(s)"
