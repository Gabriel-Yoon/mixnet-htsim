#!/bin/bash
# htsim fabric comparison over the MixNet-3 fully-measured models (mixtral8x7B, llamaMoE, qwenMoE),
# microbatch sweep, on {glass, gb200, h100} fabrics. Each model has its own node count + panels.
#   glass  = optical FB 512/512 ;  gb200 = NVLink5 domain 900 / IB 50 ;  h100 = NVLink4 450 / IB 50
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
ROOT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/mixnet-sim
BINDIR=$ROOT/mixnet-htsim/src/clos/datacenter
BIN=$BINDIR/htsim_tcp_glassfb
TG=$ROOT/taskgraph
OUT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots
mkdir -p "$OUT"; cd "$BINDIR"
CSV=$OUT/mixnet3_fabric_sweep.csv
csv_warn_truncate "$CSV" "model,mb,fabric,nodes,intra_bw,inter_bw,panel,makespan_ps,makespan_ms"
echo "model,mb,fabric,nodes,intra_bw,inter_bw,panel,makespan_ps,makespan_ms" > "$CSV"

# model -> "prefix nodes glass_panel gb200_panel h100_panel"
declare -a MODELS=(
  "mixtral8x7B_fullmeasure_dp2tp8pp1ep8  128 16 64 8"
  "llamaMoE_fullmeasure_dp2tp8pp1ep8     128 16 64 8"
  "qwenMoE_fullmeasure_dp1tp2pp1ep60     120 24 60 8"
)
# fabric -> "intra inter"
run() {  # label nodes panel intra inter prefix mb
  local label=$1 nodes=$2 panel=$3 intra=$4 inter=$5 prefix=$6 mb=$7
  local fbuf=$TG/${prefix}_mb${mb}_1L_seq1024_H200.fbuf
  [ -f "$fbuf" ] || { echo "  MISSING $fbuf"; return; }
  local log=$OUT/run_${prefix%%_*}_${label}_mb${mb}.log
  GLASS_PANEL=$panel GLASS_INTRA_BW=$intra GLASS_INTER_BW=$inter \
    "$BIN" -nodes $nodes -flowfile "$fbuf" -q 1000000 > "$log" 2>&1
  local ps; ps=$(grep "finished one iter" "$log" | grep -oE 'now [0-9]+' | tail -1 | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  local ms; ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
  local mname=${prefix%%_*}
  echo "$mname,$mb,$label,$nodes,$intra,$inter,$panel,$ps,$ms" >> "$CSV"
  echo "  [$mname $label mb$mb] $ms ms"
}

for spec in "${MODELS[@]}"; do
  read -r prefix nodes gpanel gb200panel h100panel <<< "$spec"
  echo "=== $prefix  ($nodes nodes) ==="
  for mb in 8 16 32 64; do
    run glass $nodes $gpanel     512 512 "$prefix" "$mb"
    run gb200 $nodes $gb200panel 900 50  "$prefix" "$mb"
    run h100  $nodes $h100panel  450 50  "$prefix" "$mb"
  done
done
echo "DONE -> $CSV"
column -t -s, "$CSV"
