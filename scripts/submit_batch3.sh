#!/bin/bash
# Batch 3: the 2x2 cabling x dim-route, the skew sweep, and hierarchical A2A.
#
# (1) 2x2 -- all FOUR cells, not two. The pre-fix result was an interaction:
#     cabling alone 0.97x, dim-route alone 1.36x WORSE on mesh, both together
#     1.71x better. Neither factor's effect can be read off the other's, so
#     dropping to two cells would misreport it.
#
#       mesh    dim=1  156.004 ms       portmap dim=1   91.367 ms
#       mesh    dim=0  114.375 ms       portmap dim=0  117.363 ms
#
#     All four at the common q=1064, which is what makes them comparable; this is
#     a controlled grid, not a vanishing-timeout walk, and gate_quotable already
#     treats dse_cabling_2x2 as grid rather than headline rows.
#
# (4) skew -- the weight matrices already exist and rung.sh already takes the
#     matrix as a parameter, so these are ordinary glass rungs with a different
#     argument. Full ladders, because a different skew can move the vanishing
#     point and quoting it at the unskewed q would be assuming it does not.
#
# (5) hier -- one cell at glass's own quoted q, matching how the pre-fix
#     comparison was drawn. -a2a_hier changes the collective, not the fabric.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"
RESULTS=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results

SNAP=$REPO/jobsnaps/batch3_$(date +%Y%m%d_%H%M%S)
mkdir -p "$SNAP"; cp scripts/rung.sh "$SNAP/rung.sh"; chmod +x "$SNAP/rung.sh"
RUN="$SNAP/rung.sh"

LINK_RATE_FIXED=""
if grep -q "8ULL \* 1000000000000ULL" "$REPO/src/clos/queue.h" 2>/dev/null; then
  if [ "$REPO/src/clos/datacenter/htsim_tcp_glassfb_pm" -nt "$REPO/src/clos/queue.o" ]; then
    LINK_RATE_FIXED=yes
  fi
fi
export LINK_RATE_FIXED
export HTSIM_BINARY_SHA="$(git rev-parse --short HEAD)"
[ "$LINK_RATE_FIXED" = yes ] || { echo "REFUSING: binary lacks the link-rate fix" >&2; exit 1; }
echo "link_rate_fixed=$LINK_RATE_FIXED  binary_sha=$HTSIM_BINARY_SHA"

N=0
sub () { # mem time tag env... -- args...
  local mem=$1 tm=$2 tag=$3 envs=$4; shift 4
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $tag "*) ;; *) return 0 ;; esac; fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    N=$((N + 1)); printf "  WOULD SUBMIT %-24s [%s]\n" "$tag" "$envs"; return 0
  fi
  local id
  id=$(sbatch --parsable --export=ALL${envs:+,$envs} -J "b3_$tag" -A gts-syu334-ece \
       -p cpu-medium -q inferno -N 1 -n 1 -c 4 --mem="$mem" -t "$tm" \
       -o "$REPO/slurm_b3_${tag}_%j.out" -e "$REPO/slurm_b3_${tag}_%j.err" \
       --wrap "bash $RUN $*")
  N=$((N + 1)); printf "  %-24s %s  [%s]\n" "$tag" "$id" "$envs"
}

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

echo "### (1) 2x2 cabling x dim-route, EP=32, common q=1064"
sub 12G 4:00:00 "x2_port_dim1" ""                          glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt 1064 8 "x2_port_dim1"
sub 12G 4:00:00 "x2_port_dim0" "RUNG_DIM_A2A=0"            glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt 1064 8 "x2_port_dim0"
sub 12G 4:00:00 "x2_mesh_dim1" "RUNG_NO_PORTMAP=1"         glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt 1064 8 "x2_mesh_dim1"
sub 12G 4:00:00 "x2_mesh_dim0" "RUNG_NO_PORTMAP=1,RUNG_DIM_A2A=0" glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt 1064 8 "x2_mesh_dim0"

echo "### (4) skew 1.2 and 2.0 at EP=32, full ladders"
for sk in 1p2 2p0; do
  for q in 266 533 1066 2133 4267 8533; do
    sub 12G 4:00:00 "sk${sk}_q$q" "" glass 32 256 "$L32" "wm_ep32_skew${sk}.txt" ep32_gt.txt "$q" 8 "sk${sk}_q$q"
  done
done

echo "### (5) hierarchical A2A, EP=32, at glass's quoted q"
sub 12G 4:00:00 "hier32_q2133" "RUNG_HIER=1" glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt 2133 8 "hier32_q2133"

echo
echo "submitted $N job(s)"
