#!/bin/bash
# Training cliff: EP=16 (comparable row) then EP=64 (the anchor).
#
# EP=16 FIRST AND CHEAP. ARM B's existing EP=16 data was taken at fb2 / inter 200 /
# G=1 / q=10000 / default 10 ms floor -- pre-correction transport. Reading the
# 16->32 step off it would be changing two things at once. This re-runs EP=16 at
# EXACTLY the EP=32 configuration so the step means what it says. 128 nodes, so it
# should cost well under the 649-754 s an EP=32 cell took.
#
# EP=64 ON qwen2_57b, not qwenMoE: same EP, same 512 nodes, 82k flows vs 221k, so
# 2.7x cheaper for the same fabric question. The flow-count gap is the graph's
# top-8 vs top-4 dispatch structure, not the fabric. qwenMoE is the confirmation
# run if time allows.
#
# The inter 3200 cell is the training version of "does 1600 suffice". The
# inference corner showed 1600 == 2000 and 2400 == 3200 bit-for-bit, so the two
# ends of the range are sufficient to answer it -- no need for four points.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./traincliff_logs
CSV=$RES/training_cliff.csv
csv_warn_truncate "$CSV" "workload_type,ep_source,model,ep,nodes,system,panel,elec_bw,opt_bw,inter_bw,G,q,rto_min_us,shortcut_banner,qdisc,makespan_ps,makespan_ms,rtos,flows,wall_s"
echo "workload_type,ep_source,model,ep,nodes,system,panel,elec_bw,opt_bw,inter_bw,G,q,rto_min_us,shortcut_banner,qdisc,makespan_ps,makespan_ms,rtos,flows,wall_s" > "$CSV"

cell() {  # model ep nodes fbuf wm system panel elec opt inter G scflag tag
  local model=$1 ep=$2 nodes=$3 fbuf=$4 wm=$5 sys=$6 panel=$7 elec=$8 opt=$9 inter=${10} g=${11} scflag=${12} tag=${13}
  local log=./traincliff_logs/${tag}_${SLURM_JOB_ID:-local}.log
  local t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=$panel GLASS_ELEC_BW=$elec \
  GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=$g \
    timeout 25200 ./htsim_tcp_glassfb -nodes "$nodes" -flowfile "$R/$fbuf" \
      $scflag -mtu 1500 -q 5000 -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1 - t0))

  local ps ms rtos sc qd flows
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  sc=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  [ -z "$sc" ] && sc=MISSING
  qd=$(grep -m1 'Queue discipline:' "$log" | sed 's/.*discipline: //' | awk '{print $1}')
  flows=$(grep -c 'flow_size:' "$log")
  local src="flexflow_${model}_dp2tp1pp4"

  echo "training,$src,$model,$ep,$nodes,$sys,$panel,$elec,$opt,$inter,$g,5000,100,$sc,$qd,$ps,$ms,$rtos,$flows,$wall" >> "$CSV"
  printf "  %-10s %-14s panel=%-3s inter=%-5s %11s ms rtos=%-6s sc=%-9s wall=%ss\n" \
    "ep$ep" "$sys" "$panel" "$inter" "$ms" "$rtos" "$sc" "$wall"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
Q64=qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf

echo "########## EP=16 at the EP=32 configuration (comparable row) ##########"
cell llamaMoE 16 128 "$L16" wm_ep16.txt glassfb_mesh 16 1800 384 1600 4 "-disable-intra-shortcut" ep16_glass
cell llamaMoE 16 128 "$L16" wm_ep16.txt nvl4_dom8    8   450 450   50 1 "-enable-intra-shortcut"  ep16_dom8
cell llamaMoE 16 128 "$L16" wm_ep16.txt nvl5_dom64  64   900 900  100 1 "-enable-intra-shortcut"  ep16_dom64

echo "########## EP=64 qwen2_57b (the anchor) ##########"
cell qwen2_57b 64 512 "$Q64" wm_ep64.txt glassfb_mesh 16 1800 384 1600 4 "-disable-intra-shortcut" ep64_glass_1600
cell qwen2_57b 64 512 "$Q64" wm_ep64.txt nvl4_dom8    8   450 450   50 1 "-enable-intra-shortcut"  ep64_dom8
cell qwen2_57b 64 512 "$Q64" wm_ep64.txt nvl5_dom64  64   900 900  100 1 "-enable-intra-shortcut"  ep64_dom64
echo "--- does 1600 suffice in training? the other end of the range ---"
cell qwen2_57b 64 512 "$Q64" wm_ep64.txt glassfb_mesh 16 1800 384 3200 4 "-disable-intra-shortcut" ep64_glass_3200

echo "=== DONE ==="
cat "$CSV"
