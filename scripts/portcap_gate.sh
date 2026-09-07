#!/bin/bash
# Gate the flat port cap, then use it to model NVL72 for EP <= 64.
#
# (1) GATE. Without -port-cap the binary must reproduce an existing flat row to
#     the picosecond: baseline_sweep.csv's decode/ep64/flat/400 = 410025604 ps,
#     run exactly as baseline_sweep.sbatch ran it (-speed bw*8000, -mtu 1500,
#     -q 10000). If that moves, the patch is not inert and nothing below counts.
#
# (2) The port cap changes what flat MEANS, so both readings are recorded:
#     uncapped = ideal non-blocking bound (per-node injection (N-1) x link rate)
#     capped   = switch-based crossbar (one 900 GB/s port per node)
#     Same run, one flag apart, so the gap between them IS the value of the
#     unphysical injection the published full-bisection baseline was getting.
#
# (3) NVL72-class rows for the training cliff: port-capped flat at 900 GB/s,
#     shortcut OFF (the whole domain IS the crossbar; leaving the 8-block NVLink
#     shortcut on would model a scale-up domain inside a scale-up domain).
#     Derived transport for a 900 GB/s port: BDP ~ 900 GB/s x 3 us ~ 2.7 MB
#     ~ 1800 pkts, so q=5000 is ~2.8x BDP and matches the glass rows' q.
#     Port feeder: BDP at ~1 us ~ 600 pkts, so 2400 pkts is ~4x BDP.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./portcap_logs
CSV=$RES/flat_portcap.csv
echo "arm,workload,ep,nodes,port_cap,speed_gbs,q,feeder_pkts,cap_banner,makespan_ps,makespan_ms,rtos,wall_s" > "$CSV"

EXPECT=410025604

emit() { # arm wl ep nodes cap speed q feeder log wall
  local arm=$1 wl=$2 ep=$3 nodes=$4 cap=$5 speed=$6 q=$7 feeder=$8 log=$9 wall=${10}
  local ps ms rtos banner
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  banner=$(grep -m1 'Flat port cap:' "$log" | sed 's/.*port cap: //' | awk '{print $1}')
  [ -z "$banner" ] && banner=MISSING
  echo "$arm,$wl,$ep,$nodes,$cap,$speed,$q,$feeder,$banner,$ps,$ms,$rtos,$wall" >> "$CSV"
  printf "  %-16s %-10s ep=%-4s cap=%-3s banner=%-9s %13s ps (%9s ms) rtos=%-6s wall=%ss\n" \
    "$arm" "$wl" "$ep" "$cap" "$banner" "$ps" "$ms" "$rtos" "$wall"
}

echo "########## (1) GATE: default OFF must reproduce $EXPECT ps ##########"
t0=$(date +%s)
./htsim_tcp_flat -nodes 64 -flowfile "$PB/decode_ep64.pb" -speed 3200000 -mtu 1500 -q 10000 \
  -weightmatrix "$T/wm_ep64.txt" > ./portcap_logs/gate.log 2>&1
emit gate_default decode 64 64 off 400 10000 - ./portcap_logs/gate.log $(( $(date +%s) - t0 ))
got=$(awk -F, '$1=="gate_default"{print $10}' "$CSV")
if [ "$got" = "$EXPECT" ]; then echo "  GATE PASSED (bit-exact, patch is inert)"; else echo "  GATE FAILED: $got != $EXPECT"; exit 1; fi

echo "########## (2)+(3) NVL72-class: port-capped flat @900 GB/s, shortcut irrelevant (flat has no 8-block model here) ##########"
for cfg in "16 128 llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf wm_ep16.txt" \
           "32 256 llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf wm_ep32.txt"; do
  set -- $cfg; ep=$1 nodes=$2 fb=$3 wm=$4
  for mode in capped uncapped; do
    flag=""; capl=off; feeder="-"
    if [ "$mode" = capped ]; then flag="-port-cap -port-cap-pkts 2400"; capl=on; feeder=2400; fi
    log=./portcap_logs/flat900_ep${ep}_${mode}.log
    t0=$(date +%s)
    GLASS_RTO_MIN_US=100 timeout 21600 ./htsim_tcp_flat -nodes "$nodes" -flowfile "$R/$fb" \
      -speed 7200000 $flag -mtu 1500 -q 5000 -weightmatrix "$T/$wm" > "$log" 2>&1
    emit "flat900_$mode" llamaMoE "$ep" "$nodes" "$capl" 900 5000 "$feeder" "$log" $(( $(date +%s) - t0 ))
  done
done

echo "=== DONE ==="; cat "$CSV"
