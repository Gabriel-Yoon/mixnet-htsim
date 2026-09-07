#!/bin/bash
# Attribution cell: is the EP=32 dom64 win bandwidth, or switch-hop latency?
#
# At EP=16 the dom64 near-tie evaporated once latency was matched (B17), so the
# same test has to be applied here before the 3.71x is attributed to the
# cross-domain bandwidth and the DP/PP mechanism.
#
# Glass at EP=32, everything identical to the winning cell EXCEPT every hop
# latency raised to 500 ns -- dom64's switch-hop figure. If glass still wins by
# ~3x, the win is bandwidth and the mechanism is confirmed. If it collapses, the
# claim narrows to "we remove the switch hop" and must be stated with these numbers.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./latmatch_logs
CSV=$RES/training_ep32_latmatch.csv
csv_warn_truncate "$CSV" "workload_type,model,ep,nodes,system,elec_lat_ns,opt_lat_ns,inter_lat_ns,makespan_ps,makespan_ms,rtos,wall_s"
echo "workload_type,model,ep,nodes,system,elec_lat_ns,opt_lat_ns,inter_lat_ns,makespan_ps,makespan_ms,rtos,wall_s" > "$CSV"
FB=$R/llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

run() { # tag elec_lat opt_lat inter_lat
  local tag=$1 el=$2 ol=$3 il=$4 log=./latmatch_logs/$1.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=384 GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
  GLASS_ELEC_LAT=$el GLASS_OPT_LAT=$ol GLASS_INTER_LAT=$il \
    timeout 21600 ./htsim_tcp_glassfb -nodes 256 -flowfile "$FB" \
      -disable-intra-shortcut -mtu 1500 -q 5000 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  echo "training,llamaMoE,32,256,$tag,$el,$ol,$il,$ps,$ms,$rtos,$wall" >> "$CSV"
  printf "  %-22s lat=%s/%s/%s ns -> %9s ms rtos=%-6s wall=%ss\n" "$tag" "$el" "$ol" "$il" "$ms" "$rtos" "$wall"
}

echo "### baseline (as-configured latencies, should reproduce 186.383 ms) ###"
run glass_native_lat 5 10 500
echo "### matched to dom64 switch-hop latency: every hop 500 ns ###"
run glass_matched_500 500 500 500
echo "=== DONE ==="; cat "$CSV"
