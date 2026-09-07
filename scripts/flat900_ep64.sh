#!/bin/bash
# NVL-64 row at EP=64: port-capped flat @900 GB/s, 512 nodes, qwen2_57b training.
# Cost estimate from the EP=16/32 rows: 76 s at 128 nodes, 290 s at 256, so ~3.8x
# per doubling -> roughly 20-25 min at 512. Affordable; the glass EP=64 cell took 2 h.
# Same derived transport as every other training row (q=5000, 100 us floor, mtu 1500).
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./flat64_logs
CSV=$RES/flat900_ep64.csv
csv_warn_truncate "$CSV" "paper_ref,workload_type,ep_source,model,ep,nodes,system,port_cap,speed_gbs,q,rto_min_us,mtu,cap_banner,makespan_ps,makespan_ms,rtos,wall_s"
echo "paper_ref,workload_type,ep_source,model,ep,nodes,system,port_cap,speed_gbs,q,rto_min_us,mtu,cap_banner,makespan_ps,makespan_ms,rtos,wall_s" > "$CSV"
FB=$R/qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf
run() { # tag flag caplabel
  local tag=$1 flag=$2 cap=$3 log=./flat64_logs/$1_${SLURM_JOB_ID:-local}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 25200 ./htsim_tcp_flat -nodes 512 -flowfile "$FB" \
    -speed 7200000 $flag -mtu 1500 -q 5000 -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos banner
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" "BEGIN{printf \"%.3f\", p/1e9}")
  rtos=$(grep -c "^At " "$log")
  banner=$(grep -m1 "Flat port cap:" "$log" | sed "s/.*port cap: //" | awk "{print \$1}")
  echo "cliff,training,flexflow_qwen2_57b,qwen2_57b,64,512,flat900,$cap,900,5000,100,1500,$banner,$ps,$ms,$rtos,$wall" >> "$CSV"
  printf "  %-10s cap=%-3s banner=%-9s %13s ps (%9s ms) rtos=%-6s wall=%ss\n" "$tag" "$cap" "$banner" "$ps" "$ms" "$rtos" "$wall"
}
echo "### NVL-64 at EP=64 (512 nodes) ###"
run capped   "-port-cap -port-cap-pkts 2400" on
run uncapped ""                              off
echo "=== DONE ==="; cat "$CSV"
