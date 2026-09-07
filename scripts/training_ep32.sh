#!/bin/bash
# TRAINING cliff, EP=32 -- and the timing cell that sizes the rest of the matrix.
#
# EP=32 is glass's FIRST PAST-THE-BOUNDARY point: a 16-GPU panel holds 16 experts,
# so EP=32 is the first configuration whose expert group cannot fit one panel.
# That is the row the cliff argument turns on, and it is the cheapest such row
# (256 nodes; the gate completed a full EP=32 run inside 900 s).
#
# Records WALL TIME per cell, because the immediate purpose is to learn the unit
# cost before committing to EP=64 (512 nodes) and EP=128/160 (1024/1280).
#
# Three systems, same workload, per docs/paper_todo.md C26:
#   glassfb     mesh G=4, intra 384 / inter 1600, derived transport, shortcut OFF
#   nvl4_dom8   8-GPU NVLink4 island, 450 GB/s in-domain, 50 GB/s scale-out
#   nvl5_dom64  64-GPU NVLink5 domain, 900 GB/s in-domain, 100 GB/s scale-out
#
# The NVLink baselines run with the shortcut ENABLED: they model real 8-GPU
# NVSwitch servers, where that bypass is physically correct (A4). Glass runs with
# it DISABLED: a panel has no NVLink island. This asymmetry is deliberate and is
# stated in the paper; the banner column records which each row actually used.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./train32_logs
CSV=$RES/training_cliff_ep32.csv
csv_warn_truncate "$CSV" "workload_type,ep_source,model,ep,nodes,system,panel,elec_bw,opt_bw,inter_bw,G,q,rto_min_us,shortcut_banner,qdisc,makespan_ps,makespan_ms,rtos,flows,wall_s"
echo "workload_type,ep_source,model,ep,nodes,system,panel,elec_bw,opt_bw,inter_bw,G,q,rto_min_us,shortcut_banner,qdisc,makespan_ps,makespan_ms,rtos,flows,wall_s" > "$CSV"

FB=$R/llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
NODES=256
WM=$T/wm_ep32.txt

cell() {  # system panel elec opt inter G shortcut_flag
  local sys=$1 panel=$2 elec=$3 opt=$4 inter=$5 g=$6 scflag=$7
  local log=./train32_logs/${sys}.log
  local t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=$panel GLASS_ELEC_BW=$elec \
  GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=$g \
    timeout 21600 ./htsim_tcp_glassfb -nodes $NODES -flowfile "$FB" \
      $scflag -mtu 1500 -q 5000 -weightmatrix "$WM" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1 - t0))

  local ps ms rtos sc qd flows
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  sc=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  [ -z "$sc" ] && sc=MISSING
  qd=$(grep -m1 'Queue discipline:' "$log" | sed 's/.*discipline: //' | awk '{print $1}')
  [ -z "$qd" ] && qd=MISSING
  flows=$(grep -c 'flow_size:' "$log")

  echo "training,flexflow_llamaMoE_dp2tp1pp4,llamaMoE,32,$NODES,$sys,$panel,$elec,$opt,$inter,$g,5000,100,$sc,$qd,$ps,$ms,$rtos,$flows,$wall" >> "$CSV"
  printf "  %-12s panel=%-3s %9s ms  rtos=%-6s shortcut=%-9s wall=%ss\n" \
    "$sys" "$panel" "$ms" "$rtos" "$sc" "$wall"
}

echo "########## EP=32 training cliff (3 systems) ##########"
cell glassfb_mesh 16 1800 384 1600 4 "-disable-intra-shortcut"
cell nvl4_dom8     8  450 450   50 1 "-enable-intra-shortcut"
cell nvl5_dom64   64  900 900  100 1 "-enable-intra-shortcut"

echo "=== DONE ==="
cat "$CSV"
echo
echo "=== wall-time budget for the rest of the matrix ==="
awk -F, 'NR>1{s+=$20; if($20>m) m=$20} END{
  printf "  EP=32 total %ds, slowest cell %ds\n", s, m
  printf "  EP=64  is 2x the nodes: expect roughly %d-%ds per cell\n", m*3, m*6
  printf "  EP=128 is 4x the nodes: expect roughly %d-%ds per cell\n", m*12, m*24
}' "$CSV"
