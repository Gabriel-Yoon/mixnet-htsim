#!/bin/bash
# Separate BUFFER BYTES from MTU in the transport sweep.
#
# THE CONFOUND. -q is in PACKETS, so queuesize_bytes = q * packet_size. The
# transport sweep's mtu=9000 row therefore also carried 6x the byte buffer:
#
#   base      mtu 1500  q 10000  -> 14,360,000 B   46.028 ms
#   q20000    mtu 1500  q 20000  -> 28,720,000 B    7.394 ms
#   mtu9000   mtu 9000  q 10000  -> 89,360,000 B    6.397 ms
#
# Read by byte buffer those are monotonic, so "jumbo frames remove the cliff"
# is not yet established -- buffer bytes alone may explain all of it. This is
# the same packet-size-vs--q asymmetry already fixed inside the binaries,
# recurring in the sweep DESIGN.
#
# ISO-BYTE ARM: hold bytes at ~14.36 MB and vary only MTU.
#   mtu 1500 q 10000 -> 14,360,000 B  (= base, the control)
#   mtu 9000 q  1596 -> 14,364,000 B  (0.03% high; the nearest integer q)
# If iso-byte mtu 9000 stays near 46 ms, MTU contributes nothing and buffer
# bytes are the whole story. If it drops toward 6 ms, MTU matters on its own.
#
# BUFFER LADDER at fixed mtu 1500, to locate where the cliff actually dies.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./bufmtu_logs
CSV=$RES/buffer_vs_mtu.csv
echo "arm,mtu,q,queue_bytes,inter_bw,shortcut,makespan_ps,makespan_ms,rtos" > "$CSV"

run() {  # arm mtu q inter
  local arm=$1 mtu=$2 q=$3 inter=$4
  local log=./bufmtu_logs/${arm}_mtu${mtu}_q${q}_i${inter}.log
  GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 \
    timeout 5000 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/coding_prefill_ep64.pb" \
      -enable-intra-shortcut -mtu "$mtu" -q "$q" \
      -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  local ps ms rto qb sc
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rto=$(grep -c '^At ' "$log")
  qb=$(grep -m1 '^queuesize' "$log" | awk '{print $2}')
  sc=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  echo "$arm,$mtu,$q,$qb,$inter,$sc,$ps,$ms,$rto" >> "$CSV"
  printf "  %-10s mtu=%-5s q=%-6s bytes=%-10s inter=%-5s -> %9s ms  rtos=%s\n" \
    "$arm" "$mtu" "$q" "$qb" "$inter" "$ms" "$rto"
}

# -enable-intra-shortcut throughout: this sweep must stay comparable to the
# transport_sensitivity.csv rows it is disambiguating, which predate e2fc399.

echo "########## ISO-BYTE: ~14.36 MB, MTU is the only variable ##########"
run isobyte 1500 10000 2000     # control, must reproduce 46028299484
run isobyte 9000  1596 2000
run isobyte 1500 10000 2400     # control, must reproduce 6448818088
run isobyte 9000  1596 2400

echo "########## BUFFER LADDER at mtu 1500, inter 2000 ##########"
for Q in 12000 14000 16000 18000 20000 40000; do run ladder 1500 "$Q" 2000; done

echo "########## reference: the confounded mtu 9000 row, bytes NOT held ##########"
run confounded 9000 10000 2000

echo "=== DONE rows: $(($(wc -l < "$CSV") - 1)) ==="
cat "$CSV"
