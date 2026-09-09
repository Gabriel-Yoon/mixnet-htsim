#!/bin/bash
# Batch 14: the 32-GPU panel, both arms -- the third point of the panel-size curve.
#
# 6x6 WAS ASKED FOR AND IS NOT REACHABLE. 36 divides none of the workload node
# counts, and glassfb_topology.cpp:56 answers a non-dividing panel size by silently
# setting _psize = no_of_nodes: one panel holding every GPU. Verified --
# GLASS_PANEL=36 with 128 nodes reports P=1. It would have run and produced a
# plausible number for a completely different fabric. Between 16 and 64 no other
# perfect square divides the node counts, so a square third point does not exist
# for these workloads.
#
# 32 IS A RECTANGLE, 8 rows x 4 cols, and that is a real caveat rather than a
# detail: this point varies panel SHAPE as well as size. It is carried in the grid
# column as 8x4 so no figure can quietly present it as a square.
#
# 192 GB/s per optical link is derived, not chosen: an 8x4 corner GPU has
# (8-1)+(4-1) = 10 row/col peers, 2 of them grid-adjacent and therefore electrical,
# leaving 8 optical -- and 8 x 192 = 1536 GB/s, the same per-GPU egress budget as
# 4 x 384 at 4x4 and 12 x 128 at 8x8.
#
# THE PORT MAPS WERE GENERATED FROM THE TRAFFIC AND VERIFIED. scripts/mk_p32_maps.sh
# feeds gen_port_map.py --used-pairs derived from the committed hop logs re-panelled
# by 32, then runs portmap_coverage.py on the result: 3/3, 10/10 and 36/36 pairs
# cabled at EP 16/32/64, nothing spare. The EP=128 8x8 map was generated WITHOUT
# --used-pairs and cabled 28 of 36, which cost twelve jobs.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

SNAP=$REPO/jobsnaps/batch14_$(date +%Y%m%d_%H%M%S)
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

# The mesh arm needs the gate in the FROZEN runner's binary, or it is a butterfly.
[ "$(strings "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" 2>/dev/null | grep -c GLASS_MAXDIST)" -ge 1 ] || {
  echo "REFUSING: run binary has no GLASS_MAXDIST -- the mesh arm would be a butterfly" >&2; exit 1; }
echo "run binary carries GLASS_MAXDIST"

for ep in 16 32 64; do
  if ! python3 scripts/portmap_coverage.py "experiments/portmaps/p32_ep${ep}.txt" \
        "src/clos/datacenter/tier_logs/tier_ep${ep}.hoplog" 32 > /tmp/pmc14_$$.txt 2>&1; then
    echo "REFUSING at EP=$ep -- p32 map does not cover its traffic:" >&2
    cat /tmp/pmc14_$$.txt >&2; rm -f /tmp/pmc14_$$.txt; exit 1
  fi
  printf "  EP=%-4s p32 map covers its traffic\n" "$ep"
done
rm -f /tmp/pmc14_$$.txt

OUTD=$REPO/experiments/results/paper/rungs
guard () {
  [ -e "$OUTD/$1.csv" ] && { echo "REFUSING $1: output exists" >&2; return 1; }
  squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -qx "b14_$1" && { echo "REFUSING $1: already queued" >&2; return 1; }
  return 0
}

N=0
sub () { # mem time tag args...
  local mem=$1 tm=$2 tag=$3; shift 3
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  guard "$tag" || return 0
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N+1)); printf "  WOULD SUBMIT  %-22s mem=%-5s t=%s\n" "$tag" "$mem" "$tm"; return 0
  fi
  local id
  id=$(sbatch --parsable --export=ALL -J "b14_$tag" -A gts-syu334-ece -p cpu-medium \
       -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b14_${tag}_%j.out" -e "$REPO/slurm_b14_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N+1)); printf "  %-24s %s\n" "$tag" "$id"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

export RUNG_PORT_BW=800 RUNG_PANEL=32 RUNG_PCOLS=4 RUNG_OPT_BW=256
for arm in fb mesh; do
  if [ "$arm" = mesh ]; then export RUNG_MAXDIST=1 RUNG_SYS=glassfb_mesh8x4; pre=m32
  else                        export RUNG_MAXDIST=0 RUNG_SYS=glassfb_8x4;     pre=p32; fi
  for spec in "16 128 $L16 wm_ep16.txt 8G  12:00:00 266 533 1066 2133 4267 8533" \
              "32 256 $L32 wm_ep32.txt 20G 20:00:00 533 1066 2133 4267 8533 17067" \
              "64 512 $QME wm_ep64.txt 20G 20:00:00 1066 2133 4267 8533 17067 34133"; do
    set -- $spec
    ep=$1 nodes=$2 fb=$3 wm=$4 mem=$5 tm=$6; shift 6
    echo "### $RUNG_SYS EP=$ep  (panel 32 = 8 rows x 4 cols, opt 256 GB/s)"
    for q in "$@"; do
      sub "$mem" "$tm" "${pre}_${ep}_q$q" glass "$ep" "$nodes" "$fb" "$wm" "p32_ep${ep}.txt" "$q" 8 "${pre}_${ep}_q$q"
    done
  done
done
unset RUNG_PORT_BW RUNG_PANEL RUNG_PCOLS RUNG_OPT_BW RUNG_MAXDIST RUNG_SYS

echo
echo "submitted/listed $N job(s)"
