#!/bin/bash
# Batch 13: long-link RATE sweep, and the latency-only control.
#
# ARM 1 -- RATE SWEEP. copper_fb at two more long-link rates, 50 and 200 GB/s, at
# the copper pad. With batch 12's 100 and glassfb_800's 384 this makes a four-point
# curve of makespan against long-link rate at EP 16/32/64.
#
#   200 GB/s IS A RATE POINT, NOT A COPPER CLAIM. The copper-feasible rate this
#   ablation was specified around is 100 GB/s. 200 is carried as rate_point in the
#   medium column so a figure cannot imply copper reaches 200 GB/s over a panel
#   diagonal. That distinction is in the data, not only in a caption.
#
# ARM 2 -- LATENCY-ONLY CONTROL. Glass bandwidth, copper pad: GLASS_OPT_BW=384 with
# GLASS_OPT_LAT=400. The copper arm changed two things at once, and this separates
# them -- whatever this control loses against glassfb_800 is the PAD's share of the
# 1.13 / 1.47 / 2.15x, and the remainder is bandwidth's.
#
# SIX RUNGS FOR THE CONTROL, NOT THE THREE TO SIX THAT WERE ASKED FOR. The request
# suggested running only the quoted rung and the one below it. That cannot produce
# a quotable row: the gap check requires EVERY rung below the candidate in the
# declared ladder to have reported, and at EP=64 the glass quoted rung q=8533 is the
# fourth of six, so 1066, 2133 and 4267 must all exist. A truncated ladder is the
# other option and it is the unsafe one -- the gap check only sees rungs it was told
# about, so a ladder starting high quotes at too much buffer and never notices a
# lower rung would have been clean. Batch 12 measured 4.5 / 15 / 45 min per rung at
# EP 16/32/64, so the full ladder costs under an hour and removes the question.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch13_$(date +%Y%m%d_%H%M%S)
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

grep -q 'export GLASS_OPT_LAT' "$RUN" || {
  echo "REFUSING: the frozen runner has no GLASS_OPT_LAT export -- every arm here" >&2
  echo "  would silently run at the OPTICAL pad and the control would be vacuous" >&2; exit 1; }
echo "frozen runner carries the GLASS_OPT_LAT export"

declare -A MAPS=( [16]=ep16_0_8_4.txt [32]=ep32_gt.txt [64]=ep64_gt.txt )
for ep in 16 32 64; do
  if ! python3 scripts/portmap_coverage.py "experiments/portmaps/${MAPS[$ep]}" \
        "src/clos/datacenter/tier_logs/tier_ep${ep}.hoplog" 16 > /tmp/pmc13_$$.txt 2>&1; then
    echo "REFUSING at EP=$ep -- port map does not cover its traffic:" >&2
    cat /tmp/pmc13_$$.txt >&2; rm -f /tmp/pmc13_$$.txt; exit 1
  fi
  printf "  EP=%-4s port map covers its traffic\n" "$ep"
done
rm -f /tmp/pmc13_$$.txt

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b13_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
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
  id=$(sbatch --parsable --export=ALL -J "b13_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b13_${tag}_%j.out" -e "$REPO/slurm_b13_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-24s %s\n" "$tag" "$id"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

# arm: prefix optbw sysname
run_arm () {
  local pre=$1 optbw=$2 sys=$3
  export RUNG_PORT_BW=800 RUNG_PANEL=16 RUNG_PCOLS=4 RUNG_OPT_LAT=400
  export RUNG_OPT_BW="$optbw" RUNG_SYS="$sys"
  for spec in "16 128 $L16 wm_ep16.txt ep16_0_8_4.txt 8G  12:00:00 266 533 1066 2133 4267 8533" \
              "32 256 $L32 wm_ep32.txt ep32_gt.txt    20G 20:00:00 533 1066 2133 4267 8533 17067" \
              "64 512 $QME wm_ep64.txt ep64_gt.txt    20G 20:00:00 1066 2133 4267 8533 17067 34133"; do
    set -- $spec
    local ep=$1 nodes=$2 fb=$3 wm=$4 map=$5 mem=$6 tm=$7; shift 7
    echo "### $sys EP=$ep  (long links $optbw GB/s, pad 400 ns)"
    for q in "$@"; do
      sub "$mem" "$tm" "${pre}_${ep}_q$q" glass "$ep" "$nodes" "$fb" "$wm" "$map" "$q" 8 "${pre}_${ep}_q$q"
    done
  done
  unset RUNG_PORT_BW RUNG_PANEL RUNG_PCOLS RUNG_OPT_BW RUNG_OPT_LAT RUNG_SYS
}

run_arm cu50   50  copper_fb_50
run_arm cu200  200 copper_fb_200
run_arm gp400  384 glass_pad400

echo
echo "submitted/listed $N job(s)"
