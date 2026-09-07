#!/bin/bash
# Re-run the three NVL-64 EP=16 sweep cells whose FCT logs were spliced.
#
# q=68 (max FCT 12.5839) and q=1088 (6.4933) are already clean. q=136, 272 and
# 544 share an output directory with another run, so their FCT is spliced --
# including the 100.4 ms straggler at 8.16x BDP, which is the load-bearing number
# in the buffer-vs-tail paragraph and in R4's NVL EP=16 tail line.
#
# Identical configuration to the original sweep; only -logdir is added, which the
# original lacked and which is why they collided. Makespans should reproduce
# exactly (147.051 / 281.100 / 130.797) -- that is the check that nothing else
# changed, and it is reported rather than assumed.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_N=0; _logdir() { _N=$((_N+1)); printf './logs/nvl16_%s_%s_%s' "${SLURM_JOB_ID:-local}" "$$" "$_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./nvl16_logs
CSV=$PAPER/nvl64_ep16_clean.csv
csv_open "$CSV" "paper_ref,system,ep,nodes,q,q_over_bdp,ecn_k,makespan_ms,expected_ms,reproduced,rtos,drops,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,max_fct_ms,fct_status,wall_s,status,note"
FB=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf

run () { # q expected_ms
  local q=$1 exp=$2
  local log=./nvl16_logs/q${q}_${SLURM_JOB_ID:-local}.log ld t0
  t0=$(date +%s)
  ld=$(_logdir)
  GLASS_RTO_MIN_US=100 timeout 20000 ./htsim_tcp_nvswitch_drop -logdir "$ld" -nodes 128 \
    -flowfile "$R/$FB" -nvs_domain 64 -nvs_switches 18 -nvs_link 50 -nvs_lat 250 \
    -nvs_q "$q" -nvs_ecn_k $((q / 2)) -speed 800000 -rtt 2000 -q 540 \
    -port-cap-pkts 270 -mtu 1500 -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  local wall=$(($(date +%s)-t0)) ps ms rtos drops repro
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  drops=$(grep -m1 -oE "dropcount: [0-9]+" "$log" | awk '{print $2}')
  repro=$([ "$ms" = "$exp" ] && echo yes || echo NO)
  # payload FCT (>1 MSS), the convention used everywhere else
  local st
  st=$(awk '/^FCT/{n++; v=$5+0; if($4>1436){m++; p[m]=v; s+=v}}
       END{if(m==0){print "0,0,,,,"; exit} asort(p);
           printf "%d,%d,%.4f,%.4f,%.4f,%.4f", n, m, s/m, p[int(m*0.5)+1], p[int(m*0.99)+1], p[m]}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo "0,0,,,,")
  csv_row "$CSV" paper_ref=sweep system=nvl64_pkt ep=16 nodes=128 q="$q" \
    q_over_bdp="$(awk -v q="$q" 'BEGIN{printf "%.2f", q*1500/50000}')" ecn_k=$((q/2)) \
    makespan_ms="$ms" expected_ms="$exp" reproduced="$repro" rtos="$rtos" drops="${drops:-}" \
    flows_total="$(echo "$st" | cut -d, -f1)" flows_payload="$(echo "$st" | cut -d, -f2)" \
    mean_fct_ms="$(echo "$st" | cut -d, -f3)" p50_fct_ms="$(echo "$st" | cut -d, -f4)" \
    p99_fct_ms="$(echo "$st" | cut -d, -f5)" max_fct_ms="$(echo "$st" | cut -d, -f6)" \
    fct_status=clean wall_s="$wall" status=sweep \
    note="re-run with -logdir so the FCT log is this run's alone; makespan must reproduce the original"
  printf "  q=%-5s -> %10s ms (expected %s, reproduced=%s) rtos=%-6s drops=%-8s maxFCT=%s\n" \
    "$q" "$ms" "$exp" "$repro" "$rtos" "${drops:-?}" "$(echo "$st" | cut -d, -f6)"
}

echo "########## NVL-64 EP=16: the three cells with spliced FCT logs ##########"
run 136  147.051
run 272  281.100
run 544  130.797
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-170
