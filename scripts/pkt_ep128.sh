#!/bin/bash
# Packet-level NVL-64 and HGX-8 at EP=128 (Arctic, 1024 nodes).
#
# Cost anchored on measurement, not guessed: the same model ran 625 s at 256
# nodes and 1707 s at 512, i.e. 2.73x per node-doubling, so 1024 nodes is
# ~4700 s per cell. Even at a pessimistic 4x it is under 2 h.
#
# Time was never the risk here; memory is. The EP=64 cells ran under a 96 GB
# allocation at 512 nodes with 8 domains; EP=128 is 1024 nodes and 16 domains,
# so the request is raised to 360 GB rather than discovering the ceiling two
# hours in. htsim allocates per queue, and this model instantiates S=18 switch
# chips per domain with up- and down-queues per (GPU, switch).
#
# Parameters are pkt_cliff.sh's, unchanged, extended to Arctic:
#   nvl64_pkt  D=64 S=18 L=50    nic=100  q_nvs=544  q_nic=540
#   hgx8_pkt   D=8  S=4  L=112.5 nic=50   q_nvs=1224 q_nic=270
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./pkt128_logs
CSV=$PAPER/cliff_pkt_ep128.csv
csv_open "$CSV" "paper_ref,model,workload_type,ep_source,model_name,topk,ep,mb,nodes,system,domain,switches,link_gbps,nvs_lat_ns,nic_bw,rtt_ns,q_nvs,q_over_bdp_banner,q_nic,rto_min_us,mtu,makespan_ms,rtos,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note"

ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

run () { # sys D S L nic q_nvs q_nic
  local sys=$1 D=$2 S=$3 L=$4 nic=$5 qn=$6 qc=$7
  local tag=${sys}_ep128
  local log=./pkt128_logs/${tag}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 43200 ./htsim_tcp_nvswitch -nodes 1024 -flowfile "$R/$ARC" \
    -nvs_domain "$D" -nvs_switches "$S" -nvs_link "$L" -nvs_lat 250 \
    -nvs_q "$qn" -nvs_ecn_k $((qn / 2)) \
    -speed $((nic * 8000)) -rtt 2000 -q "$qc" -port-cap-pkts $((qc / 2)) -mtu 1500 \
    -weightmatrix "$T/wm_ep128.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local ps ms rtos ld qob comp st stats
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  # the multiple comes from the banner, which computes it from the MSS
  qob=$(grep -m1 "NVSwitch queue" "$log" | grep -oE "\(([0-9.]+)x BDP" | tr -d '(x BDP' || echo "")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  stats=$(awk '/^FCT/{n++; v=$5+0; s+=v; if($4>1436){m++; p[m]=v}; if(v>mx)mx=v}
       END{if(n==0){print ",,,,,"; exit} asort(p);
           printf "%d,%d,%.4f,%.4f,%.4f,%.4f", n, m, s/n, p[int(m*0.5)+1], p[int(m*0.99)+1], mx}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo ",,,,,")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=final
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration; fi
  echo "cliff,pkt,training,flexflow_arctic,arctic,2,128,8,1024,$sys,$D,$S,$L,250,$nic,2000,$qn,$qob,$qc,100,1500,$ms,$rtos,$stats,$((t1-t0)),$st,packet-level NVSwitch; stripe=ecmp; island OFF" >> "$CSV"
  printf "  %-16s D=%-3s S=%-3s L=%-6s q=%-5s (%sx BDP) -> %10s ms rtos=%-8s wall=%ss [%s]\n" \
    "$tag" "$D" "$S" "$L" "$qn" "$qob" "$ms" "$rtos" "$((t1-t0))" "$st"
}

echo "########## EP=128 Arctic, packet-level ##########"
run nvl64_pkt 64 18 50    100 544  540
run hgx8_pkt   8  4 112.5  50 1224 270
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
