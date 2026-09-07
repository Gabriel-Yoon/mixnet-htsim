#!/bin/bash
# EP=64 cliff row on the ground-truth cabling, then its queue sweep.
#
# ep64_gt.txt is generated from fl_ep64_qme.pairs and verified here before use:
# 96 cabled == 96 used, nothing missing, nothing spare, 14-16 ports per panel.
# The rule-based map relayed one pair and posted 103067 RTOs, so the queue
# plainly binds at EP=64 and the sweep follows the row rather than waiting on it.
#
# BDP for the inter-panel port is link_bw x that port's round trip:
# 400 GB/s x 2 x 500 ns = 400 000 B = 267 packets of 1500 B. So k=2 -> q=533,
# k=4 -> q=1067, k=8 -> q=2133. The cliff row's q=1064 is k=4 to within 3 pkts;
# it is run at exactly 1064 so it is comparable with the EP=32 row.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
MAP=$PM/ep64_gt.txt
mkdir -p "$PAPER" ./gt64_logs
CSV=$PAPER/cliff_ep64_gt.csv
csv_open "$CSV" "paper_ref,model,cabling,workload_type,model_name,topk,ep,mb,nodes,panels,system,ports_lit,opt_bw,elec_bw,k,q,q_over_bdp,rto_min_us,mtu,placement,dim_a2a,relayed_pairs,completed,makespan_ms,rtos,wall_s,status,note"

QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

run () { # tag k q
  local tag=$1 k=$2 q=$3
  local log=./gt64_logs/${tag}_${SLURM_JOB_ID:-local}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$MAP" \
    timeout 25200 $BIN -nodes 512 -flowfile "$R/$QME" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos ports comp st qob
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  ports=$(grep -m1 "ports lit per panel" "$log" | grep -oE "per panel [0-9]+\.\.[0-9]+" | awk '{print $3}')
  qob=$(awk -v q="$q" 'BEGIN{printf "%.2f", (q*1500)/400000}')
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=final
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  echo "cliff,pkt_glass,portmap_ground_truth,training,qwenMoE,4,64,8,512,32,glassfb,$ports,384,1800,$k,$q,$qob,100,1500,on,on,$relay,$comp,$ms,$rtos,$((t1-t0)),$st,map from GLASS_LOG_FLOWS 96/96 pairs direct" >> "$CSV"
  printf "  %-18s k=%-3s q=%-5s %-10s relay=%-3s %10s ms  rtos=%-8s ports=%-7s wall=%ss [%s]\n" \
    "$tag" "$k" "$q" "$comp" "$relay" "$ms" "$rtos" "$ports" "$((t1-t0))" "$st"
  if [ "$relay" != 0 ]; then
    grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort | uniq -c | sort -rn | head -6 | sed 's/^/        /'
  fi
}

echo "########## EP=64 cliff row (q=1064, comparable with EP=32) ##########"
run gt64_cliff 4 1064
echo "########## queue sweep: BDP = 267 pkt, so k=2/4/8 ##########"
run gt64_k2 2 533
run gt64_k8 8 2133
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
