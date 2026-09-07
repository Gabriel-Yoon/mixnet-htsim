#!/bin/bash
# Clean 2x2 for the cabling / dim-order attribution, plus a determinism repeat.
#
# WHY NOT REUSE 186.383. That mesh row was run with `-q 5000` hardcoded
# (training_cliff.sh:34), against the port-map rows' q=1064. Comparing them
# attributes to CABLING a difference that also contains a 4.7x change in queue
# -- and this workload is acutely queue-sensitive: the NVLink sweep moved
# 147 -> 281 ms for a 2x queue change, and the port-map row moved 91.367 ->
# 85.365 for q 1064 -> 1067, a 0.3% change. So the mesh cells are re-run here at
# q=1064 with everything else at the cliff row's settings.
#
# Mesh keeps its own inter_bw=1600 and G=4: that IS the mesh cabling, and is what
# the comparison is about. Only q is being held fixed, not the cabling itself.
#
#   cabling   dim-route   cell
#   port-map  ON          91.367  (have)
#   port-map  OFF        117.363  (have)
#   mesh      ON          this
#   mesh      OFF         this
#
# The determinism repeat re-runs the port-map dim ON cell at exactly q=1064. If
# it does not return 91.367 the sweep's differences are not attributable to the
# swept variable at all, and every single-run makespan in the paper needs a
# stated repeat.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./dse_logs
CSV=$PAPER/dse_cabling_2x2.csv
csv_open "$CSV" "paper_ref,cabling,dim_a2a,ep,nodes,panels,inter_mode,inter_bw,G,q,q_over_bdp,rto_min_us,mtu,relayed_pairs,completed,makespan_ms,rtos,wall_s,status,note"

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

cell () { # tag cabling dim
  local tag=$1 cab=$2 dim=$3
  local log=./dse_logs/${tag}.log t0 t1
  t0=$(date +%s)
  if [ "$cab" = mesh ]; then
    GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
    GLASS_OPT_BW=384 GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
    GLASS_EP_PLACE=1 GLASS_DIM_A2A=$dim \
      timeout 10800 ./htsim_tcp_glassfb -nodes 256 -flowfile "$R/$L32" \
        -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  else
    GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
    GLASS_EP_PLACE=1 GLASS_DIM_A2A=$dim GLASS_PORT_MAP="$PM/ep32_gt.txt" \
      timeout 10800 ./htsim_tcp_glassfb_pm -nodes 256 -flowfile "$R/$L32" \
        -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  fi
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos comp st ibw g
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=final
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  if [ "$cab" = mesh ]; then ibw=1600; g=4; else ibw=400; g=map; fi
  echo "cliff,$cab,$dim,32,256,16,$cab,$ibw,$g,1064,4.0,100,1500,$relay,$comp,$ms,$rtos,$((t1-t0)),$st,q held at 1064 across all four cells" >> "$CSV"
  printf "  %-22s cabling=%-8s dim=%s  %-10s relay=%-3s %10s ms  rtos=%-7s wall=%ss [%s]\n" \
    "$tag" "$cab" "$dim" "$comp" "$relay" "$ms" "$rtos" "$((t1-t0))" "$st"
}

echo "########## mesh cabling at q=1064, the two missing cells ##########"
cell mesh_dim1 mesh 1
cell mesh_dim0 mesh 0
echo "########## determinism: repeat the port-map dim ON cell (expect 91.367) ##########"
cell portmap_dim1_repeat portmap 1
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
