#!/bin/bash
# Compare communication time (makespan) across htsim topologies for the paper-config MoE jobs,
# assuming a normal H100 system: leaf-spine/fat-tree & fully-connected at ConnectX-7 IB (400 Gbps
# = 50 GB/s) vs our glass-FB optical panel (512 GB/s). A glass-at-IB run isolates the topology
# benefit (same BW). makespan = last "finished one iter ... now <picosec>".
set -uo pipefail
ROOT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/mixnet-sim
BINDIR=$ROOT/mixnet-htsim/src/clos/datacenter
TG=$ROOT/taskgraph
OUT=/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots
mkdir -p "$OUT"; cd "$BINDIR"
CSV=$OUT/paper_topo_compare.csv
[ -f "$CSV" ] || echo "model,nodes,topology,link_gbps,makespan_ps,makespan_ms" > "$CSV"

IB_MBPS=400000   # 400 Gbps = 50 GB/s (H100 ConnectX-7)
mk() {  # logfile
  grep -aE "finished one iter" "$1" 2>/dev/null | grep -aoE 'now [0-9]+' | tail -1 | awk '{print $2}'
}
runrow() {  # model nodes topology link_gbps logfile
  local model=$1 nodes=$2 topo=$3 gbps=$4 log=$5
  local ps; ps=$(mk "$log"); [ -z "$ps" ] && ps=0
  local ms; ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
  echo "$model,$nodes,$topo,$gbps,$ps,$ms" >> "$CSV"
  echo "  [$model $topo @${gbps}Gbps] makespan = $ms ms"
}

# model -> "fbuf_prefix nodes panel"
declare -a JOBS=(
  "llamaMoE_paper_dp2tp1pp4_ep16top2_L32_seq4096_mb8     128 16"
  "mixtral8x7B_paper_dp2tp4pp4_ep8top2_L32_seq4096_mb8   256 16"
  "qwenMoE_paper_dp2tp1pp4_ep64top4_L24_seq4096_mb8      512 16"
)
ONLY="${ONLY:-}"   # e.g. ONLY=llamaMoE to run one

for spec in "${JOBS[@]}"; do
  read -r prefix nodes panel <<< "$spec"
  mname=${prefix%%_*}
  [ -n "$ONLY" ] && [[ "$mname" != "$ONLY" ]] && continue
  FB=$(ls $TG/${prefix}_*.fbuf 2>/dev/null | head -1)
  [ -f "$FB" ] || { echo "MISSING $prefix"; continue; }
  echo "=== $mname ($nodes devices) ==="
  # 1) fat-tree (leaf-spine) @ IB
  ./htsim_tcp_fattree -nodes $nodes -flowfile "$FB" -speed $IB_MBPS -q 1000000 > $OUT/topo_${mname}_fattree.log 2>&1
  runrow $mname $nodes fattree 400 $OUT/topo_${mname}_fattree.log
  # 2) fully-connected @ IB
  ./htsim_tcp_fc -nodes $nodes -flowfile "$FB" -speed $IB_MBPS -q 1000000 > $OUT/topo_${mname}_fc.log 2>&1
  runrow $mname $nodes fc 400 $OUT/topo_${mname}_fc.log
  # 3) glass-FB optical 512 GB/s
  GLASS_PANEL=$panel GLASS_INTRA_BW=512 GLASS_INTER_BW=512 \
    ./htsim_tcp_glassfb -nodes $nodes -flowfile "$FB" -q 1000000 > $OUT/topo_${mname}_glass512.log 2>&1
  runrow $mname $nodes glass_optical 4096 $OUT/topo_${mname}_glass512.log
  # 4) glass-FB at IB BW (50 GB/s) -> topology-only benefit
  GLASS_PANEL=$panel GLASS_INTRA_BW=50 GLASS_INTER_BW=50 \
    ./htsim_tcp_glassfb -nodes $nodes -flowfile "$FB" -q 1000000 > $OUT/topo_${mname}_glassIB.log 2>&1
  runrow $mname $nodes glass_atIB 400 $OUT/topo_${mname}_glassIB.log
done
echo "DONE -> $CSV"; column -t -s, "$CSV"
