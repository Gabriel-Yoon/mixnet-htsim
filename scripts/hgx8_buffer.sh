#!/bin/bash
# Buffer sensitivity on the HGX-8 scale-out tier, so the cliff figure does not
# stall on discovering the 4x BDP point is in a timeout regime.
#
# The derived-transport rule allows k to be chosen per tier provided it is
# printed, so this establishes k for the 50 GB/s NIC rather than assuming 4x
# carries over from the glass edge. BDP at 50 GB/s and a 2 us hop is 100 KB
# = 67 pkts, so q = 135 / 270 / 540 is 2x / 4x / 8x.
#
# 4x is the quoted row; the other two are status=sensitivity. If 4x shows tens of
# thousands of timeouts and 8x does not, 8x becomes the quoted row and the reason
# is on record here rather than in a message.
set -uo pipefail
# Unique output directory per invocation. The binary's default is a
# one-second timestamp, which two concurrent cells can share; see
# scripts/logdir_collisions.py and methods_provenance.md sub-class I.
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./island_logs
CSV=$PAPER/cliff_buffer_sensitivity.csv
csv_open "$CSV" "paper_ref,workload_type,ep_source,model,topk,ep,mb,nodes,system,island_gpus,island_bw,nic_bw,rtt_ns,q,q_over_bdp,feeder_pkts,rto_min_us,mtu,makespan_ms,rtos,flows,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note"
FB=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf

run () { # q feeder mult status
  local q=$1 feed=$2 mult=$3 st=$4
  local log=./island_logs/hgx8_buf_q${q}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 25200 ./htsim_tcp_flat -logdir "$(_logdir)" -nodes 128 -flowfile "$R/$FB" \
    -speed 400000 -rtt 2000 -port-cap -port-cap-pkts "$feed" \
    -island_gpus 8 -island_bw 450 -mtu 1500 -q "$q" \
    -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos flows ld f
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  f=$(awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if(v>mx)mx=v}
           END{if(n==0){print ",,"; exit} asort(a); printf "%.4f,%.4f,%.4f", s/n, a[int(n*0.99)], mx}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo ",,")
  echo "cliff,training,flexflow_llamaMoE,llamaMoE,2,16,8,128,hgx8,8,450,50,2000,$q,$mult,$feed,100,1500,$ms,$rtos,$flows,$f,$wall,$st,HGX-8 scale-out buffer sensitivity; BDP at 50 GB/s and 2 us = 67 pkts" >> "$CSV"
  printf "  q=%-5s (%sx BDP) feeder=%-5s -> %10s ms  rtos=%-8s wall=%ss\n" "$q" "$mult" "$feed" "$ms" "$rtos" "$wall"
}

echo "### HGX-8 EP=16, scale-out buffer sensitivity ###"
run 135 65  2 sensitivity
run 270 130 4 final
run 540 260 8 sensitivity
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-160
