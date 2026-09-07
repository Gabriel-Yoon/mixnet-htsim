#!/bin/bash
# Pin ONE NVLink latency model and re-run the nvl rows at it.
#
# THE PROBLEM. The NVLink references execute on the glassfb binary with only
# bandwidth and panel size overridden, so they inherited the topology's DEFAULT
# latencies (100/300/500 ns). The B17 rows used 500/500/500 -- the NVSwitch hop.
# So the current nvl rows are 5x more optimistic on in-domain latency than the
# B17 rows, the two sets are not on one model, and the optimism was a default
# that leaked rather than a choice anyone made.
#
# FIX. Re-run every nvl cell at the physical model: 500 ns per in-domain hop,
# sourced as the NVSwitch hop and consistent with B17. The existing 100/300/500
# rows are kept as a labelled "optimistic-for-NVLink" sensitivity. Since the win
# is bandwidth (glass and the nvl configs already share per-hop latency, so
# latency cannot be its source), nothing should flip -- and if something does,
# that is a finding.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./nvllat_logs
CSV=$RES/nvl_latency_model.csv
csv_warn_truncate "$CSV" "workload_type,model,ep,nodes,system,lat_model,elec_lat_ns,opt_lat_ns,inter_lat_ns,makespan_ps,makespan_ms,rtos,wall_s"
echo "workload_type,model,ep,nodes,system,lat_model,elec_lat_ns,opt_lat_ns,inter_lat_ns,makespan_ps,makespan_ms,rtos,wall_s" > "$CSV"

run() { # model ep nodes fbuf wm system panel elec inter latmodel el ol il
  local model=$1 ep=$2 nodes=$3 fbuf=$4 wm=$5 sys=$6 panel=$7 elec=$8 inter=$9 lm=${10} el=${11} ol=${12} il=${13}
  local log=./nvllat_logs/${sys}_ep${ep}_${lm}_${SLURM_JOB_ID:-local}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=$panel GLASS_ELEC_BW=$elec \
  GLASS_OPT_BW=$elec GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=1 \
  GLASS_ELEC_LAT=$el GLASS_OPT_LAT=$ol GLASS_INTER_LAT=$il \
    timeout 21600 ./htsim_tcp_glassfb -nodes "$nodes" -flowfile "$R/$fbuf" \
      -enable-intra-shortcut -mtu 1500 -q 5000 -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  echo "training,$model,$ep,$nodes,$sys,$lm,$el,$ol,$il,$ps,$ms,$rtos,$wall" >> "$CSV"
  printf "  ep%-3s %-11s %-10s lat=%s/%s/%s -> %11s ms rtos=%-6s wall=%ss\n" "$ep" "$sys" "$lm" "$el" "$ol" "$il" "$ms" "$rtos" "$wall"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

echo "### physical NVLink model: 500 ns per in-domain hop (NVSwitch) ###"
run llamaMoE 16 128 "$L16" wm_ep16.txt nvl4_dom8   8  450  50 physical_500 500 500 500
run llamaMoE 16 128 "$L16" wm_ep16.txt nvl5_dom64 64  900 100 physical_500 500 500 500
run llamaMoE 32 256 "$L32" wm_ep32.txt nvl4_dom8   8  450  50 physical_500 500 500 500
run llamaMoE 32 256 "$L32" wm_ep32.txt nvl5_dom64 64  900 100 physical_500 500 500 500
echo "=== DONE ==="; cat "$CSV"
