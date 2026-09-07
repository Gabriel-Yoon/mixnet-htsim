#!/bin/bash
# Is the EP=32 makespan chaotic in q at the 3-packet scale, or is 1064 near a threshold?
#
# The cliff row is 91.367 ms at q=1064. The k-sweep's first point, q=1067 -- three
# packets more, 0.3% -- returned 85.365 ms, 6.6% faster. Either the makespan is
# chaotic in q at this scale, in which case every glass row in the paper is a
# band and not a point, or 1064 sits near a threshold, in which case we say where
# it is. Both readings change how the numbers are quoted, so this runs before any
# k sweep is used for anything.
#
# q on a uniform grid straddling 1064, everything else exactly the cliff row.
# 267 pkt = 1 BDP, so the whole grid spans 3.75x to 4.22x BDP -- deliberately
# narrow: the question is sensitivity at a scale that should not matter.
#
# NOTE the paired determinism repeat lives in dse2x2.sh (port-map dim ON at
# q=1064, expected 91.367). Without it a spread here cannot be told apart from
# run-to-run variation, so read the two together.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
MAP=$PM/ep32_gt.txt
mkdir -p "$PAPER" ./qfine_logs
CSV=$PAPER/qfine_ep32.csv
csv_open "$CSV" "paper_ref,cabling,ep,nodes,q,q_over_bdp,q_pct_vs_1064,relayed_pairs,completed,makespan_ms,pct_vs_1064,rtos,max_fct_ms,wall_s,status,note"

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
BASE=91.367

run () { # q
  local q=$1
  local log=./qfine_logs/q${q}_${SLURM_JOB_ID:-local}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$MAP" \
    timeout 10800 $BIN -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos ld mx comp st qob qp mp
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  mx=$(awk '/^FCT/{v=$5+0; if(v>m)m=v} END{printf "%.4f", m}' "$ld/fct_util_out.txt" 2>/dev/null || echo "")
  qob=$(awk -v q="$q" 'BEGIN{printf "%.2f", (q*1500)/400000}')
  qp=$(awk -v q="$q" 'BEGIN{printf "%+.2f", 100*(q-1064)/1064}')
  mp=$(awk -v m="$ms" -v b="$BASE" 'BEGIN{printf "%+.2f", 100*(m-b)/b}')
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=sensitivity
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  echo "cliff,portmap_ground_truth,32,256,$q,$qob,$qp,$relay,$comp,$ms,$mp,$rtos,$mx,$((t1-t0)),$st,fine q sensitivity around the cliff row" >> "$CSV"
  printf "  q=%-5s (%s%% vs 1064, %sx BDP) -> %10s ms (%s%%)  rtos=%-7s maxFCT=%-9s [%s]\n" \
    "$q" "$qp" "$qob" "$ms" "$mp" "$rtos" "$mx" "$st"
}

echo "########## fine q grid around the EP=32 cliff row (91.367 ms at q=1064) ##########"
for q in 1000 1032 1064 1096 1128; do run "$q"; done
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
