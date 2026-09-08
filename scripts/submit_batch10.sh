#!/bin/bash
# Batch 10: the panel-size DSE -- 8x8 flattened butterfly and an 8x8 electrical mesh.
#
# Answers "why a 4x4 panel, and why not a wafer mesh" with measurements instead of
# the ASP-DAC Fig 7(a) data, which is pre-fix, pre-port-map, 100G/lane and EP=16 only
# and therefore quotable for nothing.
#
# All three arms share the paper's task graphs, port-map cabling, 200G/lane ports,
# EP-aware placement, dim-order routing and the measured-loss gate. The 4x4 arm is
# already measured (87.700 / 75.253 / 39.879 / 194.609) and is NOT re-run.
#
# OPTICAL BANDWIDTH AT 8x8. 128 GB/s per optical link, against 384 at 4x4. The
# invariant that makes this the right number is a FIXED OPTICAL EGRESS BUDGET PER
# GPU: a 4x4 corner GPU has 4 optical peers at 384 GB/s and an 8x8 corner GPU has 12
# at 128, and 4 x 384 = 12 x 128 = 1536 GB/s either way. That identity is the check;
# the inequality it was quoted from (2*deg*n + 4m <= 60, m=3.125) permits n up to 5.9
# at 4x4 and so does not by itself pin the 384 the paper uses. Recorded because a
# constant that reproduces the existing design point is worth more than one that
# merely satisfies a bound.
#
# THE MESH IS GIVEN EVERY ADVANTAGE. Same 1800 GB/s per neighbour link as the FB
# panel's electrical tier (inside the wafer-scale range: Dojo D1 900 GB/s per die
# edge, WATOS D2D 3.5-4.5 TB/s), and it keeps one MTP-16 per GPU for cross-panel
# egress even though a wafer would not have that. What it does not get is a direct
# link to a non-adjacent peer: GLASS_MAXDIST=1 builds only grid-adjacent intra links
# and routes everything else hop by hop in XY order. Verified before submission --
# at EP=16 the mesh moves ZERO bytes on the optical tier (every intra hop is now
# distance-1, hence electrical), the inter-panel bytes are unchanged, and the
# electrical bytes rise 2.69x.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch10_$(date +%Y%m%d_%H%M%S)
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

# The binary must carry the MAXDIST gate, or the mesh arm would silently be a second
# flattened butterfly -- a whole arm of the figure measuring the wrong topology.
# grep -c and a numeric test, NOT grep -q: -q exits on the first match, strings is
# killed by SIGPIPE, and this script runs under , so the pipeline
# returns 141 and a binary that DOES carry the gate is refused. The check was
# written to catch a missing gate and instead caught nothing but itself.
[ "$(strings "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" 2>/dev/null | grep -c GLASS_MAXDIST)" -ge 1 ] || {
  echo "REFUSING: htsim_tcp_glassfb_pm has no GLASS_MAXDIST -- rebuild it first" >&2; exit 1; }
echo "GLASS_MAXDIST present in the run binary"

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b10_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
  return 0
}

N=0
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  guard "$tag" || return 0
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N+1)); printf "  WOULD SUBMIT  %-20s mem=%-5s t=%-9s\n" "$tag" "$mem" "$tm"; return 0
  fi
  local id
  id=$(sbatch --parsable --export=ALL -J "b10_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b10_${tag}_%j.out" -e "$REPO/slurm_b10_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-26s %s\n" "$tag" "$id"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

# 2x..64x of the 800 GB/s port BDP (533.3 pkt at MTU 1500, RTT 4x250 ns)
QS="1066 2133 4267 8533 17067 34133"

# 8x8 geometry for both arms; the mesh differs only by MAXDIST.
export RUNG_PORT_BW=800 RUNG_PANEL=64 RUNG_PCOLS=8 RUNG_OPT_BW=128

for arm in fb mesh; do
  if [ "$arm" = mesh ]; then export RUNG_MAXDIST=1 RUNG_SYS=glassfb_mesh8x8
  else                        export RUNG_MAXDIST=0 RUNG_SYS=glassfb_8x8; fi
  echo "### 8x8 $arm"
  for spec in "16 128 $L16 wm_ep16.txt 8G 8:00:00" \
              "32 256 $L32 wm_ep32.txt 20G 12:00:00" \
              "64 512 $QME wm_ep64.txt 20G 16:00:00" \
              "128 1024 $ARC wm_ep128.txt 40G 20:00:00"; do
    set -- $spec; ep=$1 nodes=$2 fb=$3 wm=$4 mem=$5 tm=$6
    for q in $QS; do
      sub "$mem" "$tm" "${arm}64_ep${ep}_q$q" glass "$ep" "$nodes" "$fb" "$wm" "p64_ep${ep}.txt" "$q" 8 "${arm}64_ep${ep}_q$q"
    done
  done
done
unset RUNG_PORT_BW RUNG_PANEL RUNG_PCOLS RUNG_OPT_BW RUNG_MAXDIST RUNG_SYS

echo
echo "submitted/listed $N job(s)"
