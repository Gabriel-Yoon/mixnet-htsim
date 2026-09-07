#!/bin/bash
# EP=32 on the ground-truth port map, plus the dim-route attribution cell.
#
# ep32_gt.txt is generated from fl_ep32.pairs, the complete per-flow record from
# GLASS_LOG_FLOWS: all 36 cross-panel pairs cabled direct. Verified here before
# running -- 36 cabled == 36 used, nothing missing, nothing spare, no panel over
# 16 ports. The earlier maps came from an all-to-all-only extract that saw 8 of
# those 36 pairs, which is why they kept relaying (13,15), a DP pair.
#
# Two cells on the SAME map so the comparison is like-for-like:
#   dim_a2a=1  the EP=32 cliff row
#   dim_a2a=0  attribution: what dim-order routing is worth once cabling is right
#
# Gate: relay must be 0. A row with any relayed pair is recorded blocked.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
MAP=$PM/ep32_gt.txt
mkdir -p "$PAPER" ./gt_logs
CSV=$PAPER/cliff_ep32_gt.csv
csv_open "$CSV" "paper_ref,model,cabling,workload_type,model_name,topk,ep,mb,nodes,panels,system,ports_lit,opt_bw,elec_bw,q,q_over_bdp,rto_min_us,mtu,placement,dim_a2a,relayed_pairs,completed,makespan_ms,rtos,flows_a2a_only,wall_s,status,note"

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

run () { # tag dim
  local tag=$1 dim=$2
  # separate statement: bash expands every RHS before local binds any of them
  local log=./gt_logs/${tag}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=$dim GLASS_PORT_MAP="$MAP" \
    timeout 7200 $BIN -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos flows ports comp status
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ports=$(grep -m1 "ports lit per panel" "$log" | grep -oE "per panel [0-9]+\.\.[0-9]+" | awk '{print $3}')
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  if [ "$comp" = COMPLETE ] && [ "$relay" = 0 ] && [ "$ps" != 0 ]; then status=final; else status=blocked; fi
  echo "cliff,pkt_glass,portmap_ground_truth,training,llamaMoE,2,32,8,256,16,glassfb,$ports,384,1800,1064,8.0,100,1500,on,$dim,$relay,$comp,$ms,$rtos,$flows,$((t1-t0)),$status,map from GLASS_LOG_FLOWS 36/36 pairs direct" >> "$CSV"
  printf "  %-16s dim_a2a=%s  %-10s relay=%-3s %10s ms  rtos=%-7s ports=%-7s wall=%ss [%s]\n" \
    "$tag" "$dim" "$comp" "$relay" "$ms" "$rtos" "$ports" "$((t1-t0))" "$status"
  if [ "$relay" != 0 ]; then
    grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort | uniq -c | sort -rn | head -6 | sed 's/^/        /'
  fi
}

echo "########## EP=32 cliff row, ground-truth cabling, dim-order routing ON ##########"
run gt_ep32_dim1 1
echo "########## attribution: same map, dim-order routing OFF ##########"
run gt_ep32_dim0 0
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
