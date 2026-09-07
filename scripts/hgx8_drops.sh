#!/bin/bash
# Measured drop counts for HGX-8 at EP=64 and EP=128, so those rows can be quoted.
#
# WHY THESE TWO. HGX-8's timeouts are buffer-invariant at every EP measured, over
# an 18x range, identical in makespan AND in timeout count to the unit:
#
#   EP=32   q=270..4896   164.522 ms, 105 timeouts, every rung
#   EP=64   q=270..4896   144.519 ms, 2192 timeouts, every rung
#   EP=128  q=1224, 2448  365.733 ms, 138883 timeouts, both rungs so far
#
# A congestion timeout responds to buffer. These do not, at all, which is why the
# EP=32 row turned out to have 105 timeouts and ZERO drops against a counter
# validated at 2 317 980 on a mesh control. The vanishing-timeout walk therefore
# cannot ever find a zero-timeout rung for this fabric -- not because the buffer is
# too small, but because the buffer is irrelevant to whatever produces them.
#
# So the quoting rule's drop-aware branch is the one that applies: a row with
# timeouts but zero MEASURED drops is quotable. Without a drop count these rows
# fall to "loss not measured" and stay unquotable forever, and Fig 6c draws HGX-8
# hollow at EP=64 and EP=128 for want of one number per row.
#
# This does not assume the answer. If drops come back non-zero the rows stay
# unquotable and that is the finding -- the timeouts would then be real loss that
# more buffer somehow does not relieve, which would be worth a paragraph of its own.
#
# Own CSV rather than appending to quoted_row_drops.csv: csv_open truncates, and
# that table is complete at six rows and already pushed. Merged by name afterwards.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
N=./htsim_tcp_nvswitch_drop
mkdir -p "$PAPER" ./hgxd_logs
[ -x "$N" ] || { echo "FATAL: $N missing" >&2; exit 1; }
[ "$(strings "$N" 2>/dev/null | grep -c dropcount)" -ge 1 ] \
  || { echo "FATAL: $N has no drop counter -- wrong binary" >&2; exit 1; }

CSV=$PAPER/quoted_row_drops_hgx8.csv
csv_open "$CSV" "paper_ref,system,ep,nodes,q,makespan_ms,expected_ms,reproduced,rtos,drops,loss_verdict,wall_s,status,note"

QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

cell () { # ep nodes fbuf wm q q_nic expected_ms
  local ep=$1 nodes=$2 fb=$3 wm=$4 qn=$5 qc=$6 exp=$7
  local ld log t0 t1 ps ms rtos drops verdict repro
  ld=$(_logdir)
  log=./hgxd_logs/${SLURM_JOB_ID:-local}_hgx8_ep${ep}_q${qn}.log
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 30000 $N -logdir "$ld" -nodes "$nodes" -flowfile "$R/$fb" \
      -nvs_domain 8 -nvs_switches 4 -nvs_link 112.5 -nvs_lat 250 \
      -nvs_q "$qn" -nvs_ecn_k $((qn / 2)) \
      -speed 400000 -rtt 2000 -q "$qc" -port-cap-pkts $((qc / 2)) -mtu 1500 \
      -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s)

  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  drops=$(grep -m1 -oE "dropcount: [0-9]+" "$log" | awk '{print $2}')
  repro=$([ "$ms" = "$exp" ] && echo yes || echo NO)

  if [ -z "${drops:-}" ]; then verdict=not_counted
  elif [ "$drops" = "0" ] && [ "$rtos" != "0" ]; then verdict=spurious_timeouts_no_loss
  elif [ "$drops" = "0" ]; then verdict=clean
  else verdict=real_loss; fi

  csv_row "$CSV" paper_ref=drops system=hgx8_pkt ep="$ep" nodes="$nodes" q="$qn" \
    makespan_ms="$ms" expected_ms="$exp" reproduced="$repro" rtos="$rtos" \
    drops="${drops:-}" loss_verdict="$verdict" wall_s="$((t1-t0))" status=measured \
    note="drop counter validated: 2317980 on the mesh control; 0 on the island; a zero here means no loss rather than no counting"

  printf "  hgx8_pkt ep=%-4s q=%-6s %10s ms (expected %s; reproduced=%s) rtos=%-8s drops=%-9s %s [%ss]\n" \
    "$ep" "$qn" "$ms" "$exp" "$repro" "$rtos" "${drops:-?}" "$verdict" "$((t1-t0))"
}

echo "########## HGX-8 drop cells at the quoted rows ##########"
cell  64  512 "$QME" wm_ep64.txt  1224 270 144.519
cell 128 1024 "$ARC" wm_ep128.txt 1224 270 365.733
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-170
