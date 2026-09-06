#!/bin/bash
# E37: is the lossless queue path usable, and is the -queuetype flag inert?
#
# TWO PARTS, IN THIS ORDER, because the second is only worth plumbing if the
# first says the path works at all.
#
# (1) GATE. With no -queuetype, and with an explicit -queuetype ecn, the binary
#     must reproduce the derived corner's best cell to the picosecond
#     (11690301651 ps at q=5000 / floor 100us / inter 1600, shortcut OFF).
#     Anything else means the flag changed behaviour and nothing below counts.
#
# (2) VIABILITY PROBE for LOSSLESS_INPUT_ECN. NOT yet the measurement -- the
#     lossless branch of alloc_queue hardcodes its own buffer (memFromPkt(10000))
#     and ECN threshold (memFromPkt(16)), ignoring -q and GLASS_ECN_K, so this
#     run is NOT at the derived corner and its makespan is not comparable to
#     11.690 ms. What it establishes is whether the path is real:
#       - "PAUSE" lines  => backpressure is actually being exchanged. Zero PAUSE
#         means the output queue degenerated to a big ECN queue and the run is
#         not lossless, so plumbing the buffer through would be wasted work.
#       - "LOSSLESS not working!" => the lossless invariant broke (a packet that
#         should have been backpressured was dropped). Any occurrence is fatal.
#       - RTO count should be ~0. A lossless fabric does not drop, so timeouts
#         would mean loss is leaking in somewhere else.
#     Only if this passes do we plumb queuesize/ECN_K (commit 2) and re-run at
#     the derived corner for the number that goes in the paper.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./e37_logs
CSV=$RES/e37_lossless_probe.csv
echo "arm,queuetype,q,rto_min_us,inter_bw,qdisc_banner,shortcut_banner,makespan_ps,makespan_ms,rtos,pause_events,lossless_violations,verdict" > "$CSV"

EXPECT=11690301651

run() {  # arm flag label
  local arm=$1 flag=$2 label=$3
  local log=./e37_logs/${arm}.log
  GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=384 GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
    timeout 5400 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/coding_prefill_ep64.pb" \
      -disable-intra-shortcut $flag -mtu 1500 -q 5000 \
      -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  local rc=$? ps ms rtos qd sc pause viol verdict
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  qd=$(grep -m1 'Queue discipline:' "$log" | sed 's/.*discipline: //' | awk '{print $1}')
  [ -z "$qd" ] && qd=MISSING
  sc=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  pause=$(grep -c 'PAUSE' "$log")
  viol=$(grep -c 'LOSSLESS not working' "$log")

  case "$arm" in
    gate_*)
      if [ "$ps" = "$EXPECT" ]; then verdict="PASS_bitexact"; else verdict="FAIL_expected_${EXPECT}"; fi ;;
    lossless_probe)
      if [ "$rc" = "139" ]; then verdict="SEGFAULT"
      elif [ "$viol" -gt 0 ]; then verdict="FATAL_lossless_violated"
      elif [ "$ps" = "0" ]; then verdict="NO_COMPLETION(rc=$rc)"
      elif [ "$pause" -eq 0 ]; then verdict="NOT_LOSSLESS_no_pause"
      elif [ "$rtos" -gt 0 ]; then verdict="VIABLE_but_${rtos}_rtos"
      else verdict="VIABLE_lossless"; fi ;;
  esac

  echo "$arm,$label,5000,100,1600,$qd,$sc,$ps,$ms,$rtos,$pause,$viol,$verdict" >> "$CSV"
  printf "  %-16s qdisc=%-20s %14s ps (%9s ms) rtos=%-6s pause=%-7s viol=%-3s %s\n" \
    "$arm" "$qd" "$ps" "$ms" "$rtos" "$pause" "$viol" "$verdict"
}

echo "########## (1) GATE: -queuetype must be inert at its default ##########"
echo "   expect $EXPECT ps"
run gate_default  ""                              "(none)"
run gate_explicit "-queuetype ecn"                "ecn"

echo "########## (2) VIABILITY PROBE: lossless_input_ecn ##########"
echo "   NOT at the derived corner -- the lossless branch hardcodes its own buffer/K."
run lossless_probe "-queuetype lossless_input_ecn" "lossless_input_ecn"

echo "########## VERDICT ##########"
cat "$CSV"
echo
awk -F, 'NR>1{printf "  %-16s %s\n", $1, $13}' "$CSV"
