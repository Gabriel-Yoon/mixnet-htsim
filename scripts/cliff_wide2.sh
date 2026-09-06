#!/bin/bash
# Cliff sweep, Glass-FB rows only, at the NEW best buildable point 384/3200
# (one MTP-16 per gateway at 200G/lane, TH6-Davisson class). The 640/1600 rows
# in domain_cliff.csv are kept as a secondary series so the provisioning
# progression 200 -> 1600 -> 3200 stays tellable.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./cliff_logs
CSV=$RES/domain_cliff_glassfb_384_3200.csv
echo "workload,ep,nodes,config,domain,intra_bw,inter_bw,G,makespan_ps,makespan_ms,rtos" > "$CSV"
for wl in decode coding_prefill chat_prefill agentic_prefill; do
  for ep in 8 16 32 64; do
    log=./cliff_logs/glassfb384_${wl}_ep${ep}.log
    env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
        GLASS_OPT_BW=384 GLASS_INTER_BW=3200 GLASS_GW_PARALLEL=4 \
      timeout 3000 ./htsim_tcp_glassfb -nodes "$ep" -flowfile "$PB/${wl}_ep${ep}.pb" \
        -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep${ep}.txt" > "$log" 2>&1
    ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}'); rto=$(grep -c '^At ' "$log")
    echo "$wl,$ep,$ep,glassfb_384_3200,16,384,3200,4,$ps,$ms,$rto" >> "$CSV"
    echo "done: glassfb384 $wl ep=$ep -> ${ms}ms rtos=$rto"
  done
done
echo "=== DONE rows: $(($(wc -l < "$CSV") - 1)) ==="; cat "$CSV"
