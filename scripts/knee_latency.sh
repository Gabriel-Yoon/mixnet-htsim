#!/bin/bash
# (A) Locate the congestion-collapse KNEE. If the 7.1x at 3200 is a threshold
#     escape, the recommendation is "provision above X", and X may sit below
#     3200 -- in which case 100G/lane (TH5-Bailly) parts already suffice, a
#     materially weaker feasibility requirement than 200G/lane.
# (B) EP=16 matched-hop-latency control. We beat a 64-GPU 900 GB/s crossbar
#     with a degree-6 FB at 384-640 GB/s, which should not happen on bandwidth.
#     Suspect the 100ns CPO vs 500ns NVSwitch hop. Match them and see if the
#     win survives (bandwidth/topology) or evaporates (switch-hop removal).
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./knee_logs
CSV=$RES/knee_and_latency.csv
csv_warn_truncate "$CSV" "experiment,workload,ep,config,intra_bw,inter_bw,lat_ns,makespan_ps,makespan_ms,rtos"
echo "experiment,workload,ep,config,intra_bw,inter_bw,lat_ns,makespan_ps,makespan_ms,rtos" > "$CSV"

emit() { # exp wl ep cfg intra inter lat log
  local ps ms rto
  ps=$(grep "finished one iter" "$8" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}'); rto=$(grep -c '^At ' "$8")
  echo "$1,$2,$3,$4,$5,$6,$7,$ps,$ms,$rto" >> "$CSV"
  printf "  %-12s %-16s ep=%-3s %-18s intra=%-4s inter=%-5s lat=%-11s -> %9s ms rtos=%s\n" \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$ms" "$rto"
}

echo "########## (A) knee: intra fixed 384, sweep inter ##########"
for wl in coding_prefill agentic_prefill; do
  for inter in 1600 2000 2400 2800 3200; do
    log=./knee_logs/knee_${wl}_i${inter}.log
    env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
        GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 \
      timeout 4000 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/${wl}_ep64.pb" \
        -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
    emit knee "$wl" 64 glassfb 384 "$inter" "100/300/500" "$log"
  done
done

echo "########## (B) EP=16 matched hop latency ##########"
for wl in decode coding_prefill; do
  # our design at NVSwitch latency (handicap us)
  log=./knee_logs/lat_glassfb500_${wl}.log
  env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
      GLASS_INTER_BW=3200 GLASS_GW_PARALLEL=4 \
      GLASS_ELEC_LAT=500 GLASS_OPT_LAT=500 GLASS_INTER_LAT=500 \
    timeout 3000 ./htsim_tcp_glassfb -nodes 16 -flowfile "$PB/${wl}_ep16.pb" \
      -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  emit matched_lat "$wl" 16 glassfb_at500ns 384 3200 "500/500/500" "$log"

  # dom64 at CPO latency (give them our latency)
  log=./knee_logs/lat_dom64_100_${wl}.log
  env GLASS_PANEL=64 GLASS_PCOLS=64 GLASS_ELEC_BW=900 GLASS_OPT_BW=900 \
      GLASS_INTER_BW=100 GLASS_ELEC_LAT=100 GLASS_OPT_LAT=100 GLASS_INTER_LAT=100 \
    timeout 3000 ./htsim_tcp_glassfb -nodes 16 -flowfile "$PB/${wl}_ep16.pb" \
      -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  emit matched_lat "$wl" 16 dom64_at100ns 900 100 "100/100/100" "$log"

  # references at their native latencies
  log=./knee_logs/lat_glassfb_native_${wl}.log
  env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
      GLASS_INTER_BW=3200 GLASS_GW_PARALLEL=4 \
    timeout 3000 ./htsim_tcp_glassfb -nodes 16 -flowfile "$PB/${wl}_ep16.pb" \
      -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  emit matched_lat "$wl" 16 glassfb_native 384 3200 "100/300/500" "$log"

  log=./knee_logs/lat_dom64_native_${wl}.log
  env GLASS_PANEL=64 GLASS_PCOLS=64 GLASS_ELEC_BW=900 GLASS_OPT_BW=900 \
      GLASS_INTER_BW=100 GLASS_ELEC_LAT=500 GLASS_OPT_LAT=500 GLASS_INTER_LAT=500 \
    timeout 3000 ./htsim_tcp_glassfb -nodes 16 -flowfile "$PB/${wl}_ep16.pb" \
      -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  emit matched_lat "$wl" 16 dom64_native 900 100 "500/500/500" "$log"
done
echo "=== DONE rows: $(($(wc -l < "$CSV") - 1)) ==="; cat "$CSV"
