#!/bin/bash
# Attribution: split the EP=32 mesh->port-map gain (186.383 -> 92.323 ms) into
# the part from CABLING and the part from DIM-ORDER ROUTING.
#
# The 92.323 row had both changes at once, so it cannot say which did the work.
# This cell holds the port-map cabling fixed and turns dim-order A2A routing OFF,
# the one variable. Everything else is byte-for-byte the 92.323 configuration.
#
#   186.383  mesh cabling,     dim-route on   (superseded row)
#    92.323  port-map cabling, dim-route on   (pm_ep32_1221)
#      ???   port-map cabling, dim-route OFF  <- this cell
#
# Runs the untouched htsim_tcp_glassfb_pm, the same binary pm-cliff is running;
# executing a binary concurrently is safe, only relinking it would not be.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
mkdir -p "$PAPER" ./attr_logs
CSV=$PAPER/attrib_ep32.csv
csv_warn_truncate "$CSV" "paper_ref,model,cabling,ep,nodes,panels,dim_a2a,placement,q,rto_min_us,mtu,relayed_pairs,completed,makespan_ms,rtos,wall_s,status,note"
echo "paper_ref,model,cabling,ep,nodes,panels,dim_a2a,placement,q,rto_min_us,mtu,relayed_pairs,completed,makespan_ms,rtos,wall_s,status,note" > "$CSV"
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

run () { # tag dim
  local tag=$1 dim=$2
  # separate statement: bash expands every RHS before local binds any of them,
  # so ${tag} on this line would be unbound under set -u
  local log=./attr_logs/${tag}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=$dim GLASS_PORT_MAP="$PM/ep32_12_2_1.txt" \
    timeout 7200 $BIN -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos comp status
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  # Same gate as the cliff rows: a relayed pair or a timeout means not reportable.
  if [ "$comp" = COMPLETE ] && [ "$ps" != 0 ]; then status=measured; else status=blocked; fi
  echo "attrib,pkt_glass,portmap_12_2_1,32,256,16,$dim,on,1064,100,1500,$relay,$comp,$ms,$rtos,$((t1-t0)),$status,dim-order A2A routing $([ "$dim" = 1 ] && echo on || echo off)" >> "$CSV"
  printf "  %-18s dim_a2a=%s  %-10s relay=%-3s %10s ms  rtos=%-7s wall=%ss [%s]\n" \
    "$tag" "$dim" "$comp" "$relay" "$ms" "$rtos" "$((t1-t0))" "$status"
}

echo "########## EP=32, port-map cabling held fixed, dim-order routing is the only variable ##########"
run attr_ep32_dim0 0
echo "########## repeat of the 92.323 config, as an in-job control ##########"
run attr_ep32_dim1 1
echo "=== DONE ==="; column -s, -t "$CSV"
