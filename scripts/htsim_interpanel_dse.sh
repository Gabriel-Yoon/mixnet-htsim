#!/bin/bash
# Inter-panel bandwidth DESIGN SPACE EXPLORATION for glass-FB.
# Rationale: intra-panel BW is FIXED by the in-package waveguide count (~512 GB/s for a 4x4 panel),
# but the INTER-panel optical BW (fiber wavelengths/count between panels) is a FREE design parameter.
# This sweep fixes intra=512 and varies inter to find the knee -- how much inter-panel optical BW the
# a2a-dominant MoE workload needs before the step stops being inter-panel-bound. That knee sets the
# inter-panel fiber budget. Runs SEQUENTIALLY (no overlap -> avoids local oversubscription) with
# verbose output filtered (makespan only).
set -uo pipefail
ROOT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/mixnet-sim
BINDIR=$ROOT/mixnet-htsim/src/clos/datacenter
TG=$ROOT/taskgraph
OUT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots
mkdir -p "$OUT"; cd "$BINDIR"
CSV=$OUT/interpanel_dse.csv
echo "model,nodes,intra_bw,inter_bw,panel,makespan_ps,makespan_ms" > "$CSV"

INTRA=512; PANEL=16
read -r -a INTERS <<< "${INTER_BWS:-25 50 100 150 200 300 400 512 768 1024}"
# model -> "fbuf_glob nodes"
declare -a JOBS=(
  "llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024    128"
  "mixtral8x7B_paper_dp2tp4pp4_ep8top2_L4_seq1024  256"
)
ONLY="${ONLY:-}"
frun(){ "$@" 2>&1 | grep -aE 'finished one iter' | grep -aoE 'now [0-9]+' | tail -1 | awk '{print $2}'; }

for spec in "${JOBS[@]}"; do
  read -r glob nodes <<< "$spec"; m=${glob%%_*}
  [ -n "$ONLY" ] && [[ "$m" != "$ONLY" ]] && continue
  FB=$(ls $TG/${glob}_*.fbuf 2>/dev/null | head -1)
  [ -f "$FB" ] || { echo "MISSING $glob"; continue; }
  echo "=== $m ($nodes), intra fixed $INTRA GB/s ==="
  for ibw in "${INTERS[@]}"; do
    ps=$(GLASS_PANEL=$PANEL GLASS_INTRA_BW=$INTRA GLASS_INTER_BW=$ibw \
         frun ./htsim_tcp_glassfb -nodes $nodes -flowfile "$FB" -q 1000000)
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
    echo "$m,$nodes,$INTRA,$ibw,$PANEL,$ps,$ms" >> "$CSV"
    echo "  inter=$ibw GB/s -> $ms ms"
  done
done
echo "DONE -> $CSV"; column -t -s, "$CSV"
