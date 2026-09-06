#!/bin/bash
# htsim fabric comparison over the fully-measured mixtral8x22B microbatch sweep.
# Runs each mb fbuf on {glass, nvl72, ideal} via the glassfb binary (2-tier, env-configured),
# extracts the makespan (last "finished one iter ... now <picosec>"), and writes a tidy CSV.
#   compute (ideal makespan) + exposed-comm (real - ideal) = the mixnet-style breakdown.
set -uo pipefail
ROOT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/mixnet-sim
BINDIR=$ROOT/mixnet-htsim/src/clos/datacenter
BIN=$BINDIR/htsim_tcp_glassfb
TG=$ROOT/taskgraph
cd "$BINDIR"   # binary uses relative paths (logs/); must run from here
OUT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots
mkdir -p "$OUT"
CSV=$OUT/mixtral_fabric_sweep.csv
echo "model,mb,fabric,nodes,intra_bw,inter_bw,panel,makespan_ps,makespan_ms" > "$CSV"

NODES=128
run() {  # name panel intra inter fbuf mb
  local name=$1 panel=$2 intra=$3 inter=$4 fbuf=$5 mb=$6
  local log=$OUT/run_${name}_mb${mb}.log
  GLASS_PANEL=$panel GLASS_INTRA_BW=$intra GLASS_INTER_BW=$inter \
    "$BIN" -nodes $NODES -flowfile "$fbuf" -q 1000000 > "$log" 2>&1
  local ps
  ps=$(grep "finished one iter" "$log" | grep -oE 'now [0-9]+' | tail -1 | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  local ms; ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
  echo "mixtral8x22B,$mb,$name,$NODES,$intra,$inter,$panel,$ps,$ms" >> "$CSV"
  echo "  [$name mb$mb] makespan = $ms ms"
}

for mb in 8 16 32 64; do
  fbuf=$TG/mixtral8x22B_fullmeasure_dp2tp8pp1ep8_mb${mb}_1L_seq1024_H200.fbuf
  [ -f "$fbuf" ] || { echo "MISSING $fbuf"; continue; }
  echo "=== mb=$mb ==="
  run glass  16 512    512    "$fbuf" "$mb"
  run nvl72   8 450    50     "$fbuf" "$mb"
  run ideal  16 100000 100000 "$fbuf" "$mb"
done
echo "DONE -> $CSV"
column -t -s, "$CSV"
