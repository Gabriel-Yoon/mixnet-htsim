#!/bin/bash
# Port-map cliff rows. Each row is gated: it must COMPLETE (not time out) with a
# relay counter of zero, or it is recorded as blocked and not reported.
#
# Placement and dim-order relay are ON everywhere -- they were off in the first
# cliff rows, which is one of the two configuration errors being corrected here.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
mkdir -p "$PAPER" ./pmc_logs
CSV=$PAPER/cliff_portmap.csv
echo "paper_ref,model,cabling,workload_type,model_name,topk,ep,mb,nodes,panels,system,ports_lit,per_gpu_xpanel_gbs,opt_bw,elec_bw,q,q_over_bdp,rto_min_us,mtu,placement,dim_a2a,relayed_pairs,completed,makespan_ms,rtos,flows,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note" > "$CSV"

row () { # tag model topk ep nodes fbuf wm map tmo
  local tag=$1 mdl=$2 topk=$3 ep=$4 nodes=$5 fb=$6 wm=$7 map=$8 tmo=$9
  local log=./pmc_logs/${tag}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/$map" \
    timeout "$tmo" $BIN -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/$wm" > "$log" 2>&1
  local rc=$?; t1=$(date +%s); wall=$((t1-t0))
  local relay ps ms rtos flows ld f ports pergpu comp status
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  f=$(awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if(v>mx)mx=v}
           END{if(n==0){print ",,"; exit} asort(a); printf "%.4f,%.4f,%.4f", s/n, a[int(n*0.99)], mx}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo ",,")
  ports=$(grep -m1 "ports lit per panel" "$log" | grep -oE "per panel [0-9]+\.\.[0-9]+" | awk '{print $3}')
  pergpu=$(grep -m1 "per-GPU cross-panel egress" "$log" | grep -oE "egress [0-9.]+\.\.[0-9.]+" | awk '{print $2}')
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  if [ "$comp" = COMPLETE ] && [ "$relay" = 0 ] && [ "$ps" != 0 ]; then status=final; else status=blocked; fi
  local P=$((nodes / 16))
  echo "cliff,portmap,$map,training,$mdl,$topk,$ep,8,$nodes,$P,glassfb,$ports,$pergpu,384,1800,1064,4.0,100,1500,on,on,$relay,$comp,$ms,$rtos,$flows,$f,$wall,$status,port-map cabling; placement+dim-route ON" >> "$CSV"
  printf "  %-22s %-10s relay=%-3s %10s ms rtos=%-7s ports=%-7s wall=%-6ss [%s]\n" \
    "$tag" "$comp" "$relay" "$ms" "$rtos" "$ports" "$wall" "$status"
  if [ "$relay" != 0 ]; then
    echo "      unmapped pairs with counts:"
    grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort | uniq -c | sort -rn | head -8 | sed 's/^/        /'
  fi
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
Q57=qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

echo "########## EP=16 (correctness gate; A2A already intra-panel) ##########"
row pm_ep16       llamaMoE  2  16  128 "$L16" wm_ep16.txt  ep16_0_8_4.txt   1800
echo "########## EP=32 -- the first row where the A2A actually crosses panels ##########"
row pm_ep32_1221  llamaMoE  2  32  256 "$L32" wm_ep32.txt  ep32_12_2_1.txt  7200
row pm_ep32_842   llamaMoE  2  32  256 "$L32" wm_ep32.txt  ep32_8_4_2.txt   7200
echo "########## EP=64 ##########"
row pm_ep64_qme   qwenMoE   4  64  512 "$QME" wm_ep64.txt  ep64_12_2_1.txt  25200
row pm_ep64_q57   qwen2_57b 8  64  512 "$Q57" wm_ep64.txt  ep64_12_2_1.txt  25200
echo "########## EP=128 (beyond) ##########"
row pm_ep128_arc  arctic    2 128 1024 "$ARC" wm_ep128.txt ep128_12_1_1.txt 36000

echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-200
