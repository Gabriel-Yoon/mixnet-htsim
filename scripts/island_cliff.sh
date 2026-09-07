#!/bin/bash
# The faithful NVLink baselines: analytic island + port-capped flat at the NIC rate.
#
# Replaces every dom8/dom64 row, which modelled scale-out as panel-adjacency edges
# and so gave a 2-panel dom64 ONE 100 GB/s link where a real 128-GPU system has 64
# NICs per domain. This is MixNet section 7.1's substrate instead: a scale-up
# island completed analytically by ffapp at nvlink_bandwidth, plus one NIC per GPU
# into a non-blocking fabric.
#
#   HGX-8  : island 8 GPUs @450 GB/s, NIC 50 GB/s   (H100 HGX + 400G ConnectX-7)
#   NVL-64 : island 64 GPUs @900 GB/s, NIC 100 GB/s (NVL72 as modelled in MixNet 8)
#
# Disclosed optimism, both toward the incumbent and therefore conservative for us:
# the island is contention-free, and the scale-out is non-blocking with an
# egress-only port cap.
#
# DERIVED TRANSPORT PER TIER, because the NIC rate is 9-18x below the glass edge
# and reusing glass's q would be the bufferbloat we already caught once. At a 2 us
# Ethernet/IB hop: BDP = NIC_GBps x 1e9 x 2e-6 bytes.
#   50 GB/s  -> 100 KB -> 67 pkts   -> q=270 is ~4x BDP
#   100 GB/s -> 200 KB -> 134 pkts  -> q=540 is ~4x BDP
# Port feeder is sized at ~4x the one-way BDP of the same port.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results; PAPER=$RES/paper
mkdir -p "$PAPER" ./island_logs
CSV=$PAPER/cliff.csv
HDR="paper_ref,workload_type,ep_source,model,topk,ep,mb,nodes,system,binary_sha,panel,elec_bw,opt_bw,inter_bw,G,island_gpus,island_bw,nic_bw,rtt_ns,q,q_over_bdp,rto_min_us,ecn_k,mtu,shortcut_banner,makespan_ms,compute_cp_ms,compute_source,rtos,flows,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note"
[ -f "$CSV" ] || echo "$HDR" > "$CSV"

fct () { # logdir -> "mean p99 max"
  local f="$1/fct_util_out.txt"
  [ -f "$f" ] || { echo ",,"; return; }
  awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if(v>mx)mx=v}
       END{if(n==0){print ",,"; exit} asort(a);
           printf "%.4f,%.4f,%.4f", s/n, a[int(n*0.99)], mx}' "$f"
}

island () { # tag model topk ep nodes fbuf wm sys nic_gbs island_n island_bw q feeder
  local tag=$1 model=$2 topk=$3 ep=$4 nodes=$5 fb=$6 wm=$7 sys=$8 nic=$9 ign=${10} ibw=${11} q=${12} feed=${13}
  local log=./island_logs/${tag}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 30000 ./htsim_tcp_flat -nodes "$nodes" -flowfile "$R/$fb" \
    -speed $((nic * 8000)) -rtt 2000 -port-cap -port-cap-pkts "$feed" \
    -island_gpus "$ign" -island_bw "$ibw" -mtu 1500 -q "$q" \
    -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos flows ld f qob
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  f=$(fct "$ld")
  qob=$(awk -v q="$q" -v n="$nic" 'BEGIN{printf "%.2f", (q*1500)/(n*1e9*2e-6)}')
  echo "cliff,training,flexflow_${model},$model,$topk,$ep,8,$nodes,$sys,,,,,,,$ign,$ibw,$nic,2000,$q,$qob,100,,1500,island_analytic,$ms,,fbuf_cp,$rtos,$flows,$f,$wall,final,island model: analytic scale-up + port-capped non-blocking scale-out (MixNet S7.1 substrate)" >> "$CSV"
  printf "  %-22s %-8s ep=%-4s nic=%-4s island=%-3s q=%-5s (%sx BDP) -> %10s ms rtos=%-7s wall=%ss\n" \
    "$tag" "$sys" "$ep" "$nic" "$ign" "$q" "$qob" "$ms" "$rtos" "$wall"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
Q64=qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf

echo "########## GATE: EP=64 flat@900 capped, so the existing row gets a binary_sha ##########"
echo "   expect 101098059210 ps"
GLASS_RTO_MIN_US=100 timeout 25200 ./htsim_tcp_flat -nodes 512 -flowfile "$R/$Q64" \
  -speed 7200000 -port-cap -port-cap-pkts 2400 -mtu 1500 -q 5000 \
  -weightmatrix "$T/wm_ep64.txt" > ./island_logs/gate_ep64.log 2>&1
GOT=$(grep "finished one iter" ./island_logs/gate_ep64.log | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
[ "$GOT" = "101098059210" ] && echo "  GATE PASSED ($GOT) -- EP=64 flat row is attributable to 1d10a42" \
  || echo "  GATE FAILED: got $GOT, expected 101098059210"

echo "########## HGX-8: island 8 @450, NIC 50 GB/s ##########"
island hgx8_ep16 llamaMoE   2 16 128 "$L16" wm_ep16.txt hgx8 50 8 450 270 130
island hgx8_ep32 llamaMoE   2 32 256 "$L32" wm_ep32.txt hgx8 50 8 450 270 130
island hgx8_ep64 qwen2_57b  8 64 512 "$Q64" wm_ep64.txt hgx8 50 8 450 270 130

echo "########## NVL-64: island 64 @900, NIC 100 GB/s ##########"
island nvl64_ep16 llamaMoE  2 16 128 "$L16" wm_ep16.txt nvl64 100 64 900 540 270
island nvl64_ep32 llamaMoE  2 32 256 "$L32" wm_ep32.txt nvl64 100 64 900 540 270
island nvl64_ep64 qwen2_57b 8 64 512 "$Q64" wm_ep64.txt nvl64 100 64 900 540 270

echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-200
