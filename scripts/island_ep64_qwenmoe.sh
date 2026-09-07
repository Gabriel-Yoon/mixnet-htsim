#!/bin/bash
# The two missing EP=64 island cells, on qwenMoE top-4.
#
# WHY. The EP=64 island rows are qwen2_57b top-8 (88.378 NVL-64, 493.707 HGX-8)
# while the glass and packet-level EP=64 cells are qwenMoE top-4, so the EP=64
# column was not like-for-like. island_cliff.sh and pkt_cliff.sh both name the
# fbuf variable Q64 and point it at DIFFERENT models, which is how it went
# unnoticed:
#
#   island_cliff.sh:65  Q64=qwen2_57b_paper_..._ep64top8_...fbuf
#   pkt_cliff.sh:53     Q64=qwenMoE_paper_..._ep64top4_...fbuf
#
# The qwen2_57b rows are kept for the edge study; these add the comparable ones.
#
# Parameters are copied verbatim from island_cliff.sh's EP=64 invocations, model
# and top-k excepted, so the only difference from the existing rows is the
# workload. Appends to the same cliff.csv.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results; PAPER=$RES/paper
mkdir -p "$PAPER" ./island_logs
CSV=$PAPER/cliff.csv
HDR="paper_ref,workload_type,ep_source,model,topk,ep,mb,nodes,system,binary_sha,panel,elec_bw,opt_bw,inter_bw,G,island_gpus,island_bw,nic_bw,rtt_ns,q,q_over_bdp,rto_min_us,ecn_k,mtu,shortcut_banner,makespan_ms,compute_cp_ms,compute_source,rtos,flows,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note"
[ -f "$CSV" ] || echo "$HDR" > "$CSV"

fct () { # logdir -> "mean,p99,max"
  local f="$1/fct_util_out.txt"
  [ -f "$f" ] || { echo ",,"; return; }
  awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if(v>mx)mx=v}
       END{if(n==0){print ",,"; exit} asort(a);
           printf "%.4f,%.4f,%.4f", s/n, a[int(n*0.99)], mx}' "$f"
}

island () { # tag model topk ep nodes fbuf wm sys nic_gbs island_n island_bw q feeder
  local tag=$1 model=$2 topk=$3 ep=$4 nodes=$5 fb=$6 wm=$7 sys=$8 nic=$9 ign=${10} ibw=${11} q=${12} feed=${13}
  # separate statement: bash expands every RHS before local binds any of them
  local log=./island_logs/${tag}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 30000 ./htsim_tcp_flat -nodes "$nodes" -flowfile "$R/$fb" \
    -speed $((nic * 8000)) -rtt 2000 -port-cap -port-cap-pkts "$feed" \
    -island_gpus "$ign" -island_bw "$ibw" -mtu 1500 -q "$q" \
    -weightmatrix "$T/$wm" > "$log" 2>&1
  local rc=$?; t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos flows ld f qob st
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  f=$(fct "$ld")
  # BDP = NIC rate x RTT, the same definition the NVSwitch banner uses
  # ("BDP over one port for the round trip"). rtt is 2000 ns here.
  qob=$(awk -v q="$q" -v n="$nic" 'BEGIN{printf "%.2f", (q*1500)/(n*1e9*2e-6)}')
  # status derived from the run, never asserted
  st=final
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration; fi
  echo "cliff,training,flexflow_${model},$model,$topk,$ep,8,$nodes,$sys,,,,,,,$ign,$ibw,$nic,2000,$q,$qob,100,,1500,island_analytic,$ms,,fbuf_cp,$rtos,$flows,$f,$wall,$st,island model: analytic scale-up + port-capped non-blocking scale-out (MixNet S7.1 substrate); qwenMoE top-4 for like-for-like EP=64" >> "$CSV"
  printf "  %-22s %-8s ep=%-4s nic=%-4s island=%-3s q=%-5s (%sx BDP) -> %10s ms rtos=%-7s wall=%ss [%s]\n" \
    "$tag" "$sys" "$ep" "$nic" "$ign" "$q" "$qob" "$ms" "$rtos" "$wall" "$st"
}

QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

echo "########## EP=64 island rows on qwenMoE top-4 (like-for-like with glass and pkt) ##########"
island nvl64_ep64_qme qwenMoE 4 64 512 "$QME" wm_ep64.txt nvl64 100 64 900 540 270
island hgx8_ep64_qme  qwenMoE 4 64 512 "$QME" wm_ep64.txt hgx8   50  8 450 270 130
echo "=== DONE ==="
