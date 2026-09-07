#!/bin/bash
# Gates for the packet-level NVSwitch model.
#
# G4 (reduction): with one switch chip at the full per-GPU rate, zero hop latency and
#     a huge queue, the domain degenerates to a single non-blocking pipe -- i.e. the
#     analytic island's own claim. EP=16 LLaMA-MoE must land within a few percent of
#     the island+flat row's 86.508 ms. Not bit-exact: queues vs an analytic completion.
# G3 (determinism): same command twice, identical makespan.
# G1 (single-flow bandwidth): derived from the FCT file rather than a synthetic
#     2-GPU benchmark -- the largest completed flow's bytes/FCT is the achieved
#     per-flow rate, which is what mode 1's one-link limit predicts.
set -uo pipefail
# Unique output directory per invocation. The binary's default is a
# one-second timestamp, which two concurrent cells can share; see
# scripts/logdir_collisions.py and methods_provenance.md sub-class I.
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./nvs_logs
CSV=$PAPER/nvswitch_gates.csv
csv_open "$CSV" "gate,config,makespan_ps,makespan_ms,rtos,flows,max_flow_GB,max_flow_fct_ms,single_flow_GBps,note"
FB=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf

run () { # tag args...
  local tag=$1; shift
  local log=./nvs_logs/${tag}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=100 timeout 20000 ./htsim_tcp_nvswitch -logdir "$(_logdir)" -nodes 128 -flowfile "$R/$FB" \
    -mtu 1500 -weightmatrix "$T/wm_ep16.txt" "$@" > "$log" 2>&1
  local ps ms rtos flows ld
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  # largest flow and its achieved rate
  local big
  big=$(awk '/^FCT/{if($4+0>mb){mb=$4+0; ms2=$5+0}} END{if(mb>0) printf "%.4f,%.4f,%.2f", mb/1e9, ms2, (mb/1e9)/(ms2/1000); else printf ",,"}' \
        "$ld/fct_util_out.txt" 2>/dev/null || printf ",,")
  echo "$tag,$*,$ps,$ms,$rtos,$flows,$big," >> "$CSV"
  printf "  %-18s %10s ms  rtos=%-6s flows=%-8s single-flow: %s\n" "$tag" "$ms" "$rtos" "$flows" "$big"
}

echo "### G4: reduction to the island (expect ~86.508 ms, within a few %) ###"
run G4_reduce -nvs_domain 8 -nvs_switches 1 -nvs_link 900 -nvs_lat 0 -nvs_q 200000 -nvs_ecn_k 100000 -speed 7200000 -rtt 2000 -q 5000 -port-cap-pkts 2400
echo "### G3: determinism (same command twice) ###"
run G3_run1 -nvs_domain 64 -nvs_switches 18 -nvs_link 50 -nvs_lat 250 -nvs_q 136 -nvs_ecn_k 68 -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270
run G3_run2 -nvs_domain 64 -nvs_switches 18 -nvs_link 50 -nvs_lat 250 -nvs_q 136 -nvs_ecn_k 68 -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270
echo "### G1: the NVL-64 configuration as it will actually run ###"
run G1_nvl64 -nvs_domain 64 -nvs_switches 18 -nvs_link 50 -nvs_lat 250 -nvs_q 136 -nvs_ecn_k 68 -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270

echo "=== VERDICT ==="
awk -F, 'NR>1{print "  "$1": "$4" ms, rtos="$5", single-flow "$9" GB/s"}' "$CSV"
G4=$(awk -F, '$1=="G4_reduce"{print $4}' "$CSV")
R1=$(awk -F, '$1=="G3_run1"{print $3}' "$CSV"); R2=$(awk -F, '$1=="G3_run2"{print $3}' "$CSV")
echo "  G4 vs island 86.508: $G4  (delta $(awk -v a="$G4" 'BEGIN{printf "%+.1f%%", (a-86.508)/86.508*100}'))"
[ "$R1" = "$R2" ] && echo "  G3 PASS (deterministic: $R1)" || echo "  G3 FAIL ($R1 vs $R2)"
cat "$CSV"
csv_close
