#!/bin/bash
# Inter-panel optical bandwidth sweep (the glass-FB thesis knob).
# Fixes intra-panel BW (in-package waveguide, 512 GB/s) and panel size (16), and sweeps the
# INTER-panel optical-fiber BW from NVL72-IB class (~50) up to glass-optical (>=512). Shows where
# the step stops being inter-panel-bound -- i.e. how much inter-panel optical BW the workload needs.
#   bash scripts/htsim_inter_bw_sweep.sh                  # mixtral8x22B mb16,mb64
#   MBS="64" INTRA=512 bash scripts/htsim_inter_bw_sweep.sh
set -uo pipefail
ROOT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/mixnet-sim
BINDIR=$ROOT/mixnet-htsim/src/clos/datacenter
BIN=$BINDIR/htsim_tcp_glassfb
TG=$ROOT/taskgraph
OUT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots
mkdir -p "$OUT"; cd "$BINDIR"
CSV=$OUT/mixtral_inter_bw_sweep.csv
echo "model,mb,intra_bw,inter_bw,panel,nodes,makespan_ps,makespan_ms" > "$CSV"

NODES=128; PANEL=16
INTRA="${INTRA:-512}"
read -r -a MB_ARR <<< "${MBS:-16 64}"
read -r -a BW_ARR <<< "${INTER_BWS:-25 50 100 150 200 300 400 512 768 1024}"

for mb in "${MB_ARR[@]}"; do
  fbuf=$TG/mixtral8x22B_fullmeasure_dp2tp8pp1ep8_mb${mb}_1L_seq1024_H200.fbuf
  [ -f "$fbuf" ] || { echo "MISSING $fbuf"; continue; }
  echo "=== mb=$mb  (intra fixed $INTRA GB/s) ==="
  for ibw in "${BW_ARR[@]}"; do
    log=$OUT/run_interbw_mb${mb}_${ibw}.log
    GLASS_PANEL=$PANEL GLASS_INTRA_BW=$INTRA GLASS_INTER_BW=$ibw \
      "$BIN" -nodes $NODES -flowfile "$fbuf" -q 1000000 > "$log" 2>&1
    ps=$(grep "finished one iter" "$log" | grep -oE 'now [0-9]+' | tail -1 | awk '{print $2}')
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
    echo "mixtral8x22B,$mb,$INTRA,$ibw,$PANEL,$NODES,$ps,$ms" >> "$CSV"
    echo "  inter_bw=$ibw GB/s -> $ms ms"
  done
done
echo "DONE -> $CSV"
column -t -s, "$CSV"
