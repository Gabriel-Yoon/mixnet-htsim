#!/bin/bash
# The physically-derived transport corner: q x RTO floor x inter provisioning.
#
# WHY THIS REPLACES THE KNOB-AT-A-TIME SWEEP. Every earlier sweep was centred on
# a datacenter-Ethernet default (q=10000 pkts = 14.4 MB, 10 ms RTO floor,
# 1500 B MTU) that has no physical relationship to an on-package glass fabric.
# Varying x2/-:-2 around that point and picking a winner is not defensible.
#
# DERIVATION (bandwidth-delay product, 1500 B packets):
#   intra-panel  384 GB/s, RTT ~1 us      -> BDP 384 KB   =  256 pkts
#   inter-panel  2400/G=4 = 600 GB/s,
#                RTT ~3 us with queueing  -> BDP 1.8 MB   = 1200 pkts
#   well-provisioned buffer = 2-4x BDP    -> q ~ 500-5000
# So the old q=10000 is ~8x BDP on the inter link and ~37x on intra: bufferbloat,
# which inflates the RTT estimate and is why the 10 ms floor was ever reached.
#
# THE OPEN QUESTION THIS ANSWERS. The two corrections push opposite ways -- a
# smaller buffer causes MORE timeouts (q=5000 gave 1097 RTOs at inter 2000),
# a smaller floor makes each one far cheaper -- and they have never been run
# together. This is that corner. Outcomes, all publishable:
#   (a) the timeout regime ends between two inter values -> the provisioning
#       claim survives, conditioned on derived transport
#   (b) it never ends -> the fabric needs ECN scaled to BDP, a real design
#       statement (GLASS_ECN_K exists for it)
#   (c) it is already gone at 1600 -> the provisioning story was a bufferbloat
#       artifact and one MTP-16 at 100G/lane suffices
#
# CAVEAT, deliberately not hidden: -q sets EVERY queue in the topology, but the
# two tiers have different BDPs (256 vs 1200 pkts). No single q is 2-4x BDP for
# both -- q=1000 is ~4x intra but under 1x inter, q=5000 is ~4x inter but ~20x
# intra. The sweep therefore reports a compromise, and if the answer turns out to
# be q-sensitive in a way that splits the tiers, the fix is a per-tier queue knob
# rather than a better choice of single q.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./corner_logs
CSV=$RES/derived_corner.csv
csv_warn_truncate "$CSV" "q,queue_bytes,bdp_ratio_intra,bdp_ratio_inter,rto_min_us,inter_bw,shortcut,makespan_ps,makespan_ms,rtos,rto_waves"
echo "q,queue_bytes,bdp_ratio_intra,bdp_ratio_inter,rto_min_us,inter_bw,shortcut,makespan_ps,makespan_ms,rtos,rto_waves" > "$CSV"

run() {  # q rto_us inter
  local q=$1 rto=$2 inter=$3
  local log=./corner_logs/q${q}_rto${rto}_i${inter}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=$rto GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=384 GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 \
    timeout 5000 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/coding_prefill_ep64.pb" \
      -disable-intra-shortcut -mtu 1500 -q "$q" \
      -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  local ps ms n waves qb sc ri re
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  n=$(grep -c '^At ' "$log")
  waves=$(grep '^At ' "$log" | awk '{print $2}' | sort -n | uniq | wc -l)
  qb=$(grep -m1 '^queuesize' "$log" | awk '{print $2}')
  sc=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  ri=$(awk -v q="$q" 'BEGIN{printf "%.1f", q/256}')
  re=$(awk -v q="$q" 'BEGIN{printf "%.1f", q/1200}')
  echo "$q,$qb,$ri,$re,$rto,$inter,$sc,$ps,$ms,$n,$waves" >> "$CSV"
  printf "  q=%-6s (%.1fx intra BDP, %.1fx inter BDP) floor=%-5sus inter=%-5s -> %9s ms  rtos=%-6s waves=%s\n" \
    "$q" "$ri" "$re" "$rto" "$inter" "$ms" "$n" "$waves"
}

for Q in 1000 2000 5000; do
  for FLOOR in 100 1000; do
    echo "########## q=$Q  floor=${FLOOR}us ##########"
    for INTER in 1600 2000 2400 3200; do run "$Q" "$FLOOR" "$INTER"; done
  done
done

echo "=== DONE rows: $(($(wc -l < "$CSV") - 1)) ==="
cat "$CSV"
echo
echo "=== where does the timeout regime end? (rtos by q x floor x inter) ==="
awk -F, 'NR>1{printf "q=%-6s floor=%-5s inter=%-5s rtos=%-7s %s ms\n",$1,$5,$6,$10,$9}' "$CSV"
