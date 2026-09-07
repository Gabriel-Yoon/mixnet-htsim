#!/bin/bash
# (0) Port-cap attribution gate, then (1-3) the EP=64 edge confound controls.
#
# GATE. The port-capped flat rows were produced from an uncommitted binary. Under
# the rule in docs/methods_provenance.md sub-class D, "the committed source is
# identical" is not attribution -- a binary built from the SHA has to reproduce
# them. Expect 410025604 ps (decode ep64 flat @400), 86507648398 ps (EP=16 capped)
# and 67821406601 ps (EP=32 capped).
#
# THE CONFOUND. EP=64 @3200 came out 3.9x WORSE than @1600 (901.005 vs 229.042 ms),
# while EP=32 @3200 was 2.30x BETTER. Two things differ besides the edge:
#   (a) the buffer was NOT re-derived. Both EP=64 rows ran at queuesize 7180000
#       (q=5000). Per gateway link that is 400 GB/s at 1600 and 800 GB/s at 3200,
#       so with a ~3 us RTT the buffer is 5.98x BDP at 1600 but only 2.99x at 3200.
#       Doubling the edge halved the relative buffer depth.
#   (b) EP=32 is llamaMoE top-2; EP=64 is qwen2_57b top-8, roughly 4x the A2A
#       volume per token. Model and top-k move with EP.
# Each control removes one.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./edge_logs
GCSV=$RES/portcap_attribution.csv
ECSV=$RES/edge_ep64.csv
echo "check,expected_ps,got_ps,match" > "$GCSV"
echo "paper_ref,workload_type,ep_source,model,topk,ep,nodes,inter_bw,q,queue_bytes,bdp_mult,rto_min_us,makespan_ps,makespan_ms,rtos,wall_s" > "$ECSV"

gate () { # tag expected cmd...
  local tag=$1 exp=$2; shift 2
  local log=./edge_logs/gate_${tag}.log
  "$@" > "$log" 2>&1
  local ps; ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  local m=FAIL; [ "$ps" = "$exp" ] && m=PASS
  echo "$tag,$exp,$ps,$m" >> "$GCSV"
  printf "  %-16s expect %14s got %14s  %s\n" "$tag" "$exp" "$ps" "$m"
}

echo "########## (0) PORT-CAP ATTRIBUTION GATE (rebuild from 1d10a42) ##########"
gate flat_default 410025604 ./htsim_tcp_flat -nodes 64 -flowfile "$PB/decode_ep64.pb" \
  -speed 3200000 -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep64.txt"
gate flat900_ep16_capped 86507648398 env GLASS_RTO_MIN_US=100 ./htsim_tcp_flat -nodes 128 \
  -flowfile "$R/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf" \
  -speed 7200000 -port-cap -port-cap-pkts 2400 -mtu 1500 -q 5000 -weightmatrix "$T/wm_ep16.txt"
gate flat900_ep32_capped 67821406601 env GLASS_RTO_MIN_US=100 ./htsim_tcp_flat -nodes 256 \
  -flowfile "$R/llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf" \
  -speed 7200000 -port-cap -port-cap-pkts 2400 -mtu 1500 -q 5000 -weightmatrix "$T/wm_ep32.txt"

edge () { # model topk fbuf wm ep nodes inter q tag
  local model=$1 topk=$2 fb=$3 wm=$4 ep=$5 nodes=$6 inter=$7 q=$8 tag=$9
  local log=./edge_logs/${tag}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=384 GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 \
    timeout 30000 ./htsim_tcp_glassfb -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos qb bdp
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  qb=$(grep -m1 '^queuesize' "$log" | awk '{print $2}')
  # per-gateway link rate = inter/4; BDP at 3 us
  bdp=$(awk -v q="$qb" -v i="$inter" 'BEGIN{printf "%.2f", q/((i/4)*1e9*3e-6)}')
  echo "edge_ep64,training,flexflow_${model},$model,$topk,$ep,$nodes,$inter,$q,$qb,$bdp,100,$ps,$ms,$rtos,$wall" >> "$ECSV"
  printf "  %-12s top%-2s inter=%-5s q=%-6s (%sx BDP) -> %10s ms rtos=%-6s wall=%ss\n" \
    "$model" "$topk" "$inter" "$q" "$bdp" "$ms" "$rtos" "$wall"
}

Q57=qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

echo "########## (1) buffer confound: 3200 at the SAME BDP multiple as 1600 ##########"
echo "   q=10000 doubles the buffer so 3200 sees ~5.98x BDP, matching the 1600 row"
edge qwen2_57b 8 "$Q57" wm_ep64.txt 64 512 3200 10000 ep64_q57_3200_q10k
echo "########## (3) monotonicity: 2400 between the two points ##########"
edge qwen2_57b 8 "$Q57" wm_ep64.txt 64 512 2400 5000  ep64_q57_2400
echo "########## (2) model confound: qwenMoE top-4, same EP ##########"
edge qwenMoE   4 "$QME" wm_ep64.txt 64 512 1600 5000  ep64_qme_1600
edge qwenMoE   4 "$QME" wm_ep64.txt 64 512 3200 5000  ep64_qme_3200

echo "=== DONE ==="; cat "$GCSV"; echo; cat "$ECSV"
