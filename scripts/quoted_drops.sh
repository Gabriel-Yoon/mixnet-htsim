#!/bin/bash
# A measured loss count for every quoted row, not only the exception.
#
# The HGX-8 rows are quoted with "105 timeouts, 0 drops". A reader is entitled to
# ask what the other rows drop, and the honest answer should be measured rather
# than assumed to be zero because their timeout count is zero. A row with zero
# timeouts can still have dropped packets recovered by fast retransmit.
#
# Same configuration as each quoted row, on the drop-instrumented binaries. The
# counter is validated: 2317980 drops on the mesh control, 0 on the island.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_N=0; _logdir() { _N=$((_N+1)); printf './logs/qd_%s_%s_%s' "${SLURM_JOB_ID:-local}" "$$" "$_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./qd_logs
CSV=$PAPER/quoted_row_drops.csv
csv_open "$CSV" "paper_ref,system,ep,nodes,q,makespan_ms,rtos,drops,loss_verdict,wall_s,status,note"

G=./htsim_tcp_glassfb_drop
N=./htsim_tcp_nvswitch_drop

emit () { # system ep nodes q log wall
  local sys=$1 ep=$2 nodes=$3 q=$4 log=$5 wall=$6
  local ps ms rtos drops verdict
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  drops=$(grep -m1 -oE "dropcount: [0-9]+" "$log" | awk '{print $2}')
  if [ -z "$drops" ]; then verdict=not_reported
  elif [ "$drops" = "0" ] && [ "$rtos" = "0" ]; then verdict=clean
  elif [ "$drops" = "0" ]; then verdict=spurious_timeouts_no_loss
  else verdict=real_loss; fi
  csv_row "$CSV" paper_ref=drops system="$sys" ep="$ep" nodes="$nodes" q="$q" \
    makespan_ms="$ms" rtos="$rtos" drops="${drops:-}" loss_verdict="$verdict" \
    wall_s="$wall" status=measured \
    note="drop counter validated: 2317980 on the mesh control, 0 on the island; zero here means no loss, not no counting"
  printf "  %-12s ep=%-4s q=%-6s %10s ms  timeouts=%-8s drops=%-10s %s\n" \
    "$sys" "$ep" "$q" "$ms" "$rtos" "${drops:-?}" "$verdict"
}

glass () { # ep nodes fbuf wm map q
  local ep=$1 nodes=$2 fb=$3 wm=$4 map=$5 q=$6 t0=$(date +%s)
  local log=./qd_logs/glass_ep${ep}_q${q}.log
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/$map" \
    timeout 30000 $G -logdir "$(_logdir)" -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/$wm" > "$log" 2>&1
  emit glassfb "$ep" "$nodes" "$q" "$log" "$(($(date +%s)-t0))"
}

pkt () { # sys ep nodes fbuf wm D S L nic qn qc
  local sys=$1 ep=$2 nodes=$3 fb=$4 wm=$5 D=$6 S=$7 L=$8 nic=$9 qn=${10} qc=${11} t0=$(date +%s)
  local log=./qd_logs/${sys}_ep${ep}_q${qn}.log
  GLASS_RTO_MIN_US=100 timeout 30000 $N -logdir "$(_logdir)" -nodes "$nodes" \
    -flowfile "$R/$fb" -nvs_domain "$D" -nvs_switches "$S" -nvs_link "$L" -nvs_lat 250 \
    -nvs_q "$qn" -nvs_ecn_k $((qn/2)) -speed $((nic*8000)) -rtt 2000 -q "$qc" \
    -port-cap-pkts $((qc/2)) -mtu 1500 -weightmatrix "$T/$wm" > "$log" 2>&1
  emit "$sys" "$ep" "$nodes" "$qn" "$log" "$(($(date +%s)-t0))"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

echo "########## glass quoted rows ##########"
glass 16 128 "$L16" wm_ep16.txt ep16_0_8_4.txt 1064
glass 32 256 "$L32" wm_ep32.txt ep32_gt.txt    2133
echo "########## incumbent quoted rows ##########"
pkt nvl64_pkt 32 256 "$L32" wm_ep32.txt 64 18 50    100 1088 540
pkt nvl64_pkt 64 512 "$QME" wm_ep64.txt 64 18 50    100 2176 540
pkt hgx8_pkt  32 256 "$L32" wm_ep32.txt  8  4 112.5  50 1224 270
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-140
