#!/bin/bash
# Buffer sensitivity on the EP=32 ground-truth cabling row.
#
# Only run if the ep32_gt row shows RTOs > 0, i.e. the queue actually binds.
#
# The canonical BDP for the inter-panel tier is link_bw * 4 * one-way latency.
# The run banner reports lat 100/300/500 ns, so 4*lat = 2 us, and at the 400 GB/s
# port rate BDP = 800 000 B = 533.3 packets of 1500 B. Hence:
#
#   k=2  q=1067   (the cliff row's q=1064 is this point, to within 3 packets)
#   k=4  q=2133
#   k=8  q=4267
#
# q is the ONLY variable; cabling, placement and dim-order routing are held at
# the cliff row's settings. ECN marking is kept at q/2 as elsewhere, so the
# marking threshold scales with the queue rather than becoming a second variable.
#
# Note the history this is checking against: the original 2400 GB/s "cliff" was
# largely a 10 ms RTO floor plus bufferbloat, so a bigger queue is not assumed
# to be better here. Both directions are reported.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
MAP=$PM/ep32_gt.txt
mkdir -p "$PAPER" ./gtk_logs
CSV=$PAPER/cliff_ep32_gt_ksweep.csv
csv_open "$CSV" "paper_ref,model,cabling,ep,nodes,panels,k,q,q_over_bdp,ecn_k,rto_min_us,mtu,relayed_pairs,completed,makespan_ms,rtos,wall_s,status,note"

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

run () { # k q
  local k=$1 q=$2
  local log=./gtk_logs/gt_k${k}.log t0 t1
  local ek=$((q / 2))
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$MAP" \
    timeout 10800 $BIN -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos comp st
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  # status derived from the run, never asserted
  st=sensitivity
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  echo "cliff,pkt_glass,portmap_ground_truth,32,256,16,$k,$q,$k.0,$ek,100,1500,$relay,$comp,$ms,$rtos,$((t1-t0)),$st,buffer sensitivity on the ground-truth cabling; BDP=800000 B at 400 GB/s x 4x500 ns" >> "$CSV"
  printf "  k=%-2s q=%-5s ecn_k=%-5s %-10s relay=%-3s %10s ms  rtos=%-8s wall=%ss [%s]\n" \
    "$k" "$q" "$ek" "$comp" "$relay" "$ms" "$rtos" "$((t1-t0))" "$st"
}

echo "########## EP=32 ground-truth cabling, buffer sweep (q only) ##########"
run 2 1067
run 4 2133
run 8 4267
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
