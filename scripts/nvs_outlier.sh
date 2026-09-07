#!/bin/bash
# The 7.81x BDP outlier in the NVLink queue sweep, reproduced and characterised.
#
# The sweep is non-monotonic in makespan while monotonic in RTOs:
#
#   queue (banner)   makespan    RTOs    mean FCT   max FCT
#   1.95x BDP        151.895     6423    0.2110     12.5839
#   3.91x            147.051     1227    0.1251     12.7167
#   7.81x            281.100      166    0.1247    100.4170   <- outlier
#   15.62x           130.797        -         -          -
#   31.25x           130.295        -         -          -
#
# The mean FCT at 7.81x is the LOWEST of the three and its RTO count is the
# lowest, yet its makespan is nearly double: a single 10.3 MB flow took 100.4 ms
# where the same flow class finishes in ~12.6 ms at smaller queues. So this is a
# tail, not congestion -- the makespan is one straggler, and a larger buffer
# converts many shallow losses into a few very deep ones.
#
# Two cells: the outlier repeated for determinism, and its neighbour at 3.91x
# repeated as a control, so "it reproduced" cannot be an artifact of the machine
# or the binary on the day.
#
# Also dumps the slowest flows and the RTO backoff depth, to check whether the
# straggler is the glass 3200 GB/s signature (a small number of flows in deep
# exponential backoff) or something else.
set -uo pipefail
# Unique output directory per invocation. The binary's default is a
# one-second timestamp, which two concurrent cells can share; see
# scripts/logdir_collisions.py and methods_provenance.md sub-class I.
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./nvsout_logs
CSV=$PAPER/nvl64_outlier.csv
csv_open "$CSV" "paper_ref,system,ep,k_nominal,q_pkts,q_over_bdp_banner,ecn_k,makespan_ms,rtos,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,max_fct_ms,max_flow_bytes,wall_s,status,note"

FB=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf

run () { # k q
  local k=$1 q=$2
  local log=./nvsout_logs/out_k${k}.log t0 t1
  local ek=$((q / 2))
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 20000 ./htsim_tcp_nvswitch -logdir "$(_logdir)" -nodes 128 -flowfile "$R/$FB" \
    -nvs_domain 64 -nvs_switches 18 -nvs_link 50 -nvs_lat 250 -nvs_q "$q" -nvs_ecn_k "$ek" \
    -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270 -mtu 1500 \
    -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local ps ms rtos ld qob st stats
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  # take the multiple from the banner: the simulator computes it from the MSS
  # (1436 B), not 1500, so recomputing it by hand gives a different number.
  qob=$(grep -m1 "NVSwitch queue" "$log" | grep -oE "\(([0-9.]+)x BDP" | tr -d '(x BDP' || echo "")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  stats=$(awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if($4>1436){m++; p[m]=v}; if(v>mx){mx=v; mxb=$4}}
       END{if(n==0){print ",,,,,,"; exit} asort(p);
           printf "%d,%d,%.4f,%.4f,%.4f,%.4f,%d", n, m, s/n, p[int(m*0.5)+1], p[int(m*0.99)+1], mx, mxb}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo ",,,,,,")
  st=sensitivity
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration; fi
  echo "cliff,nvl64_pkt,16,$k,$q,$qob,$ek,$ms,$rtos,$stats,$((t1-t0)),$st,outlier reproduction; FCT triple over payload flows only" >> "$CSV"
  printf "  k_nominal=%-3s q=%-5s (%sx BDP) -> %10s ms  rtos=%-7s wall=%ss [%s]\n" \
    "$k" "$q" "$qob" "$ms" "$rtos" "$((t1-t0))" "$st"
  echo "     slowest 5 flows (src dst bytes fct_ms):"
  awk '/^FCT/{printf "       %s %s %s %s\n", $2, $3, $4, $5}' "$ld/fct_util_out.txt" 2>/dev/null \
    | sort -k4 -rn | head -5
  echo "     RTO backoff depth (occurrences per doubling):"
  grep -oE "RTO [0-9]+ ?(us|ms)?" "$log" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | sed 's/^/       /' || true
}

echo "########## the outlier, repeated ##########"
run 16 272
echo "########## its neighbour, as a control ##########"
run 8 136
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
