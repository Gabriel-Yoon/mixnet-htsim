#!/bin/bash
# Buffer sweep on the NVLink switch ports. The quoted NVL row must be the one
# most favourable to NVLink the model can produce -- charging it a buffer penalty
# we cannot source would be the dom8 bufferbloat trap in reverse.
# BDP over one 50 GB/s port at 500 ns RTT = 25 KB = 17 pkts.
set -uo pipefail
# Unique output directory per invocation. The binary's default is a
# one-second timestamp, which two concurrent cells can share; see
# scripts/logdir_collisions.py and methods_provenance.md sub-class I.
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./nvs_logs
CSV=$PAPER/nvl64_ksweep.csv
csv_open "$CSV" "paper_ref,system,ep,k,q_pkts,ecn_k,makespan_ms,rtos,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status"
FB=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf

for k in 4 8 16 32 64; do
  # BDP_PKTS: 50 GB/s over the NVLink round trip (4 hops x 250 ns = 1000 ns),
  # at 1500 B = 33 packets. The 17 here was 2*nvs_lat, the stale figure from
  # nvswitch_model_design.md that the code never used, so every k label this
  # sweep produced was 2x the multiple actually run.
  BDP_PKTS=33
  q=$((BDP_PKTS * k)); ek=$((q / 2))
  log=./nvs_logs/ksweep_k${k}.log; t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 20000 ./htsim_tcp_nvswitch -logdir "$(_logdir)" -nodes 128 -flowfile "$R/$FB" \
    -nvs_domain 64 -nvs_switches 18 -nvs_link 50 -nvs_lat 250 -nvs_q $q -nvs_ecn_k $ek \
    -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270 -mtu 1500 \
    -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  rc=$?; t1=$(date +%s)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  # A row's status must be derived, not asserted: makespan 0.000 means the
  # run never emitted "finished one iter", so it produced no iteration at all.
  st=sensitivity
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration; fi
  rtos=$(grep -c '^At ' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  f=$(awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if(v>mx)mx=v} END{if(n==0){print ",,"; exit} asort(a); printf "%.4f,%.4f,%.4f", s/n, a[int(n*0.99)], mx}' "$ld/fct_util_out.txt" 2>/dev/null || echo ",,")
  echo "cliff,nvl64_pkt,16,$k,$q,$ek,$ms,$rtos,$f,$((t1-t0)),$st" >> "$CSV"
  printf "  k=%-3s q=%-5s -> %10s ms  rtos=%-7s fct(mean,p99,max)=%s\n" "$k" "$q" "$ms" "$rtos" "$f"
done
csv_close
echo "=== DONE ==="; cat "$CSV"
