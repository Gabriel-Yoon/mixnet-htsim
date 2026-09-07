#!/bin/bash
# Batch 5: two glass EP=128 drop cells, and a 200G/lane ladder that is NOT submitted.
#
# (1) DROP CELLS at q=1066 and q=2133. Glass EP=128 has no timeout-free rung -- five
# of six in, 601806 / 394052 / 238854 RTO at q=533/1066/2133 and 6883 at 17067 --
# so the walk currently has no quotable row at all. But HGX-8 EP=128 posts 139 653
# timeouts with ZERO measured drops, identical to the picosecond at three buffers,
# and the drop-aware branch quotes it. If glass's timeouts here are the same kind,
# the same branch quotes glass's best rung solid instead of hollow, and the EP=128
# paragraph changes from "no clean point on this port map" to "quoted at 273.5 with
# spurious timeouts". If they come with real loss, the paragraph stands as written.
# Either answer is worth two cells; neither can be guessed.
#
# The drop build must REPRODUCE the plain build's makespan -- 273.493 at q=1066 and
# 274.510 at q=2133 -- or the drop count belongs to some other run. collect_rungs
# refuses to merge a drop twin whose makespan disagrees, so this is enforced, not
# just hoped for. Each cell gets its own logdir (rung.sh calls _logdir once per
# cell), which is the failure that cost batch 4 its nvl64 tail.
#
# (2) A 200G/lane glass EP=128 ladder, DRY RUN ONLY. GLASS_PORT_BW=800 raises each
# inter-panel port from 400 to 800 GB/s on the SAME ep128_gt.txt cabling -- the
# paper's stated option for the panel boundary. It is not submitted here and this
# script will not submit it: it is listed so the decision has a cost attached. Run
# it with SUBMIT_800=1 only after the user has said to.
#
# rung.sh carries RUNG_PORT_BW for this, added with the script: without it the rate
# would have to leak through the environment, the row's note would not record it,
# and the walk would be indistinguishable from a 400 GB/s one in every table.
#
# 800 GB/s is also a rate the OLD arithmetic could not have measured: floor(1000/800)
# is 1, so a pre-fix run of this ladder would have modelled a 1000 GB/s port.
#
# BDP for the 800 GB/s port, using the same convention as every other glass rung:
#   q_over_bdp = (q * MTU) / (link_bw * RTT), MTU 1500, RTT = 4 x 250 ns = 1 us
#   1x BDP at 800 GB/s = 800e9 * 1e-6 / 1500 = 533.3 pkt
# so the six rungs are 2x/4x/8x/16x/32x/64x of that, the same ladder shape the
# 400 GB/s walk used at 533..17067 -- which is 2x..64x of ITS 266.7 pkt BDP.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch5_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"

LINK_RATE_FIXED=""
grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null &&
  [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_drop" -nt "$REPO/src/clos/queue.o" ] &&
  LINK_RATE_FIXED=yes
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
[ "$LINK_RATE_FIXED" = yes ] || { echo "REFUSING: htsim_tcp_glassfb_drop lacks the link-rate fix" >&2; exit 1; }
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"

# Refuse a cell whose output already exists. submit_all_rungs.sh was once run a
# second time as a test that the guard would refuse, at a moment the guard
# correctly passed: 78 duplicate jobs and 36 double-written rung files.
OUTD=$REPO/experiments/results/paper/rungs
guard () { # tag
  if [ -e "$OUTD/$1.csv" ]; then
    echo "REFUSING $1: $OUTD/$1.csv already exists -- delete it deliberately or use another tag" >&2
    return 1
  fi
  if squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b5_$1"; then
    echo "REFUSING $1: a job named b5_$1 is already queued" >&2
    return 1
  fi
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
  id=$(sbatch --parsable --export=ALL -J "b5_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b5_${tag}_%j.out" -e "$REPO/slurm_b5_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-22s %s\n" "$tag" "$id"
}

ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

echo "### (1) glass EP=128 drop cells; makespans must reproduce 273.493 / 274.510"
for q in 1066 2133; do
  sub 40G 20:00:00 "gd128_q$q" glassdrop 128 1024 "$ARC" wm_ep128.txt ep128_gt.txt "$q" 8 "gd128_q$q"
done

echo
echo "### (2) 200G/lane ladder (GLASS_PORT_BW=800) -- NOT SUBMITTED unless SUBMIT_800=1"
if [ "${SUBMIT_800:-0}" = 1 ]; then
  echo "    SUBMIT_800=1 given: these will be submitted"
else
  echo "    listing only; set SUBMIT_800=1 to submit, and only when told to"
fi
# Exported, not set as a command prefix: sbatch --export=ALL exports the
# environment sbatch itself has, and relying on a prefix to reach it through two
# function frames is the kind of subtlety that has already cost this pipeline a
# whole loop once (an unbound $R aborted a submitter AFTER it deleted files).
[ "${SUBMIT_800:-0}" = 1 ] && export RUNG_PORT_BW=800
for q in 1066 2133 4267 8533 17067 34133; do
  tag="g128b800_q$q"
  if [ "${SUBMIT_800:-0}" = 1 ]; then
    sub 40G 20:00:00 "$tag" glass 128 1024 "$ARC" wm_ep128.txt ep128_gt.txt "$q" 8 "$tag"
  else
    printf "  WOULD SUBMIT  %-16s mem=%-5s t=%-9s  RUNG_PORT_BW=800 glass 128 1024 %s wm_ep128.txt ep128_gt.txt %s 8 %s\n" \
      "$tag" 40G 20:00:00 "$ARC" "$q" "$tag"
  fi
done
unset RUNG_PORT_BW

echo
echo "submitted/listed $N job(s) in section (1)"
