#!/bin/bash
# EP=128 packet-level: walk the incumbent to its vanishing-timeout buffer.
#
# The first EP=128 cell is measured: nvl64_pkt at q=544 (15.6x BDP) gives
# 331.611 ms with 17152 timeouts, so it is not quotable, exactly as at EP=32
# (73 at 15.6x, clear at 31x) and EP=64 (7237 at 15.6x, 13 at 31x). The trend
# says EP=128 needs more than 31x, so the walk starts there.
#
# MEMORY. The measured peak RSS of the 1024-node run is 17.4 GB. I requested
# 180 GB for it, and 360 GB before that -- a 10-20x over-request that sat on
# (Priority) waiting for a whole large node. 32 GB is ~1.8x the measurement,
# which is headroom rather than guesswork, and schedules on far more nodes.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./pkt128vt_logs
CSV=$PAPER/pkt128_vanishing_timeout.csv
csv_open "$CSV" "paper_ref,model,system,model_name,topk,ep,nodes,domain,switches,link_gbps,nic_bw,q_nvs,q_over_bdp_banner,ecn_k,q_nic,makespan_ms,rtos,peak_rss_GB,wall_s,quoted,status,note"
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

sweep () { # sys D S L nic qc q...
  local sys=$1 D=$2 S=$3 L=$4 nic=$5 qc=$6; shift 6
  local qn log t0 t1 rc ps ms rtos qob peak st quoted found=0
  for qn in "$@"; do
    log=./pkt128vt_logs/${sys}_q${qn}.log
    t0=$(date +%s)
    GLASS_RTO_MIN_US=100 /usr/bin/time -v timeout 43200 ./htsim_tcp_nvswitch -logdir "$(_logdir)" \
      -nodes 1024 -flowfile "$R/$ARC" \
      -nvs_domain "$D" -nvs_switches "$S" -nvs_link "$L" -nvs_lat 250 \
      -nvs_q "$qn" -nvs_ecn_k $((qn / 2)) \
      -speed $((nic * 8000)) -rtt 2000 -q "$qc" -port-cap-pkts $((qc / 2)) -mtu 1500 \
      -weightmatrix "$T/wm_ep128.txt" > "$log" 2>&1
    rc=$?; t1=$(date +%s)
    ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
    rtos=$(grep -c '^At ' "$log")
    qob=$(grep -m1 "NVSwitch queue" "$log" | grep -oE "\(([0-9.]+)x BDP" | tr -d '(x BDP' || echo "")
    peak=$(grep -m1 "Maximum resident set size" "$log" | grep -oE "[0-9]+$" | awk '{printf "%.1f", $1/1048576}')
    st=sweep
    if [ "$rc" = "124" ]; then st=truncated; elif [ "$ps" = "0" ]; then st=no_iteration; fi
    quoted=no
    if [ "$st" = sweep ] && [ "$rtos" = "0" ] && [ "$found" = 0 ]; then quoted=yes; found=1; fi
    csv_row "$CSV" paper_ref=cliff model=pkt system="$sys" model_name=arctic topk=2 ep=128 \
      nodes=1024 domain="$D" switches="$S" link_gbps="$L" nic_bw="$nic" q_nvs="$qn" \
      q_over_bdp_banner="$qob" ecn_k=$((qn/2)) q_nic="$qc" makespan_ms="$ms" rtos="$rtos" \
      peak_rss_GB="${peak:-}" wall_s="$((t1-t0))" quoted="$quoted" status="$st" \
      note="EP=128 incumbent vanishing-timeout walk; q=544 measured 331.611 ms with 17152 timeouts"
    printf "  %-10s q=%-6s (%sx) -> %10s ms rtos=%-8s peakRSS=%-7sGB wall=%-6ss quoted=%s [%s]\n" \
      "$sys" "$qn" "$qob" "$ms" "$rtos" "${peak:-?}" "$((t1-t0))" "$quoted" "$st"
    [ "$found" = 1 ] && break
  done
  [ "$found" = 0 ] && echo "      NOTE: no zero-timeout point for $sys at EP=128 in the swept range"
}

echo "########## EP=128 Arctic, incumbent buffer walk ##########"
sweep nvl64_pkt 64 18 50    100 540  1088 2176 4352
sweep hgx8_pkt   8  4 112.5  50 270  2448 4896 9792
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-165
