#!/bin/bash
# (1) Did we pick the wrong point on the MTP-16 Pareto? Both are buildable in
#     the same ~60 WG budget (wg_budget.py --pareto):
#       n=5 -> 640 intra + 1 MTP-16/gateway = 1600 GB/s edge   (current choice)
#       n=3 -> 384 intra + 2 MTP-16/gateway = 3200 GB/s edge   (untested)
#     2 ports/gateway = one 6.4T optical engine, which TH5-Bailly already ships.
#     Test on the only two configs that actually moved: coding/agentic @ EP=64.
#
# (2) One-knob diagnostic in the EP>panel regime. The earlier one-knob run was
#     mb=4 / EP=16 / single panel, where inter carries almost nothing -- its
#     "inter x8 does nothing" result must NOT be carried over to EP=64, where
#     inter carries the A2A itself.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb
T=../../../test
RES=../../../experiments/results
mkdir -p "$RES" ./ep64_logs
CSV=$RES/ep64_designpoint.csv
csv_warn_truncate "$CSV" "experiment,workload,ep,opt_bw,inter_bw,G,makespan_ps,makespan_ms,rtos"
echo "experiment,workload,ep,opt_bw,inter_bw,G,makespan_ps,makespan_ms,rtos" > "$CSV"

run() {  # exp wl ep opt inter g
  local exp=$1 wl=$2 ep=$3 opt=$4 inter=$5 g=$6
  local log=./ep64_logs/${exp}_${wl}_ep${ep}_o${opt}_i${inter}_g${g}_${SLURM_JOB_ID:-local}.log
  env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
      GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=$g \
    timeout 4000 ./htsim_tcp_glassfb -nodes "$ep" -flowfile "$PB/${wl}_ep${ep}.pb" \
      -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep${ep}.txt" > "$log" 2>&1
  local ps ms rto
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rto=$(grep -c '^At ' "$log")
  echo "$exp,$wl,$ep,$opt,$inter,$g,$ps,$ms,$rto" >> "$CSV"
  printf "  %-14s %-16s opt=%-4s inter=%-5s G=%s -> %9s ms  rtos=%s\n" "$exp" "$wl" "$opt" "$inter" "$g" "$ms" "$rto"
}

echo "########## (1) Pareto design point: 640/1600 vs 384/3200 at EP=64 ##########"
for wl in coding_prefill agentic_prefill; do
  run pareto_n5 "$wl" 64 640 1600 4
  run pareto_n3 "$wl" 64 384 3200 4
done

echo "########## (2) one-knob diagnostic at EP=64 (EP>panel regime) ##########"
for wl in coding_prefill; do
  run knob_base    "$wl" 64 640 1600 4
  run knob_opt_x2  "$wl" 64 1280 1600 4
  run knob_opt_half "$wl" 64 320 1600 4
  run knob_inter_x2 "$wl" 64 640 3200 4
  run knob_inter_half "$wl" 64 640 800 4
  run knob_g1      "$wl" 64 640 1600 1
done
echo "=== DONE, rows: $(($(wc -l < "$CSV") - 1)) ==="
cat "$CSV"
