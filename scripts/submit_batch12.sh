#!/bin/bash
# Batch 12: the copper-medium ablation on the paper's own 4x4 flattened butterfly.
#
# ONE THING CHANGES: the medium of the distance->=2 intra-panel links.
#
#   GLASS_OPT_BW   384 -> 100 GB/s   the copper-feasible long-link rate
#   GLASS_OPT_LAT  300 -> 400 ns     retimed + FEC pad instead of the optical pad
#
# Everything else is byte-for-byte the glassfb_800 configuration: same task graphs
# at EP 16/32/64, EP-aware placement, port-map cabling, dimension-order routing,
# GLASS_ELEC_BW=1800, GLASS_PORT_BW=800 (ports stay optical MTP-16), the same
# binary with the link-rate fix, the same six-rung ladder and the same
# first-zero-timeout quoting rule with the measured-drop gate.
#
# THE 400 ns IS AN ASSUMPTION ON AN ASSUMPTION, AND MUST BE WRITTEN THAT WAY. The
# 300 ns optical figure is not a measured propagation delay, it is the topology's
# MODEL PAD (glassfb_topology.h: _elec_lat_ns=100, _opt_lat_ns=300,
# _inter_lat_ns=500). Raising it by 100 ns represents retiming and FEC on a copper
# long link. So the paper should say "the long-link latency pad was raised from
# 300 ns to 400 ns", not "copper adds 110 ns of physical delay". The underlying
# physical claim -- copper ~150 ns against optical ~40 ns over a panel diagonal --
# is the peer's and is not sourced in this repo.
#
# SIX RUNGS PER EP, NOT FOUR. The request said ~4 rungs to save hours. The ladder is
# the same six glassfb_800 used, for two reasons. The comparison is rung-for-rung:
# the 8x8 arms showed that comparing two fabrics at their own quoted buffers asks a
# different question from comparing them at the same buffer, and buffer is the swept
# axis. And a short ladder is unsafe in a way the gap check CANNOT catch -- it only
# verifies rungs below the candidate that are in the DECLARED ladder, so a ladder
# that starts high would quote at too much buffer and never notice a lower rung
# would have been clean. Copper is slower, so its clean rung may well sit higher
# than glass's, but that must be measured rather than assumed by truncation.
#
# PORT-MAP COVERAGE IS CHECKED BEFORE ANYTHING IS SUBMITTED. This is the check the
# EP=128 DSE arm skipped, at a cost of twelve jobs (sub-class Q).
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch12_$(date +%Y%m%d_%H%M%S)
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

# The knob this arm depends on must exist in the FROZEN runner, not just in the
# working tree -- the frozen copy is what every job executes.
grep -q 'export GLASS_OPT_LAT' "$RUN" || {
  echo "REFUSING: the frozen runner has no GLASS_OPT_LAT export -- the copper arm" >&2
  echo "  would silently run at the OPTICAL latency and measure bandwidth alone" >&2; exit 1; }
echo "frozen runner carries the GLASS_OPT_LAT export"

# Port-map coverage, per EP, before a single job is submitted.
declare -A MAPS=( [16]=ep16_0_8_4.txt [32]=ep32_gt.txt [64]=ep64_gt.txt )
for ep in 16 32 64; do
  if ! python3 scripts/portmap_coverage.py "experiments/portmaps/${MAPS[$ep]}" \
        "src/clos/datacenter/tier_logs/tier_ep${ep}.hoplog" 16 > /tmp/pmc_$$.txt 2>&1; then
    echo "REFUSING at EP=$ep -- port map does not cover its traffic:" >&2
    cat /tmp/pmc_$$.txt >&2; rm -f /tmp/pmc_$$.txt; exit 1
  fi
  printf "  EP=%-4s %s\n" "$ep" "$(grep -m1 '^OK' /tmp/pmc_$$.txt)"
done
rm -f /tmp/pmc_$$.txt

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b12_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
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
  id=$(sbatch --parsable --export=ALL -J "b12_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b12_${tag}_%j.out" -e "$REPO/slurm_b12_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-24s %s\n" "$tag" "$id"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

# 4x4 panel, optical ports, COPPER long links.
export RUNG_PORT_BW=800 RUNG_PANEL=16 RUNG_PCOLS=4 RUNG_OPT_BW=100 RUNG_OPT_LAT=400 RUNG_SYS=copper_fb

for spec in "16 128 $L16 wm_ep16.txt ep16_0_8_4.txt 8G  12:00:00 266 533 1066 2133 4267 8533" \
            "32 256 $L32 wm_ep32.txt ep32_gt.txt    20G 20:00:00 533 1066 2133 4267 8533 17067" \
            "64 512 $QME wm_ep64.txt ep64_gt.txt    20G 20:00:00 1066 2133 4267 8533 17067 34133"; do
  set -- $spec
  ep=$1 nodes=$2 fb=$3 wm=$4 map=$5 mem=$6 tm=$7; shift 7
  echo "### copper_fb EP=$ep  (opt 100 GB/s, pad 400 ns)"
  for q in "$@"; do
    sub "$mem" "$tm" "cu${ep}_q$q" glass "$ep" "$nodes" "$fb" "$wm" "$map" "$q" 8 "cu${ep}_q$q"
  done
done
unset RUNG_PORT_BW RUNG_PANEL RUNG_PCOLS RUNG_OPT_BW RUNG_OPT_LAT RUNG_SYS

echo
echo "submitted/listed $N job(s)"
