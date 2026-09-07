#!/bin/bash
# Are the HGX-8 island's 105 timeouts spurious, or real loss?
#
# They fire at one instant (t=58 ms) from 54 sources and are invariant to a 4x
# change in BOTH the queue and the port feeder -- 105 at q=270, 540 and 1080,
# with the makespan identical to the microsecond at 164.522 ms. That is the
# signature of a synchronized first window expiring against a 100 us RTO floor
# on a fabric whose RTT is microseconds, not of drops.
#
# Two independent discriminators, because the RTO floor alone would only show
# that raising it removes the timer firing -- which it must, by construction:
#
#   A. RTO floor 1000 us. If the 105 vanish AND the makespan is unchanged, the
#      retransmissions were not recovering anything.
#   B. Drop counts from the run itself, at the SAME floor as the original. If
#      the fabric reports no drops, the timeouts cannot have been loss-driven,
#      and that holds without changing the transport at all.
#
# B is the stronger test: A changes the thing being measured, B does not.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./islrto_logs
CSV=$PAPER/island_rto_probe.csv
csv_open "$CSV" "paper_ref,system,ep,nodes,q,feeder_pkts,rto_min_us,makespan_ms,rtos,rto_times,drops_reported,vs_100us_ms,status,note"
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
BASE=164.522

run () { # rto_us
  local rto=$1
  local log=./islrto_logs/hgx8_ep32_rto${rto}_${SLURM_JOB_ID:-local}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=$rto timeout 30000 ./htsim_tcp_flat -logdir "$(_logdir)" \
    -nodes 256 -flowfile "$R/$L32" \
    -speed 400000 -rtt 2000 -port-cap -port-cap-pkts 135 \
    -island_gpus 8 -island_bw 450 -mtu 1500 -q 270 \
    -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local ps ms rtos times drops dv st
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  times=$(grep "^At " "$log" | awk '{print $2}' | sort -u | tr '\n' ' ')
  # any drop accounting the simulator emits, at whatever name it uses
  drops=$(grep -ciE "drop(ped)?[^a-z]" "$log" 2>/dev/null || echo 0)
  dv=$(awk -v a="$ms" -v b="$BASE" 'BEGIN{printf "%+.4f", a-b}')
  st=probe; [ "$rc" = "124" ] && st=truncated; [ "$ps" = "0" ] && st=no_iteration
  csv_row "$CSV" paper_ref=probe system=hgx8 ep=32 nodes=256 q=270 feeder_pkts=135 \
    rto_min_us="$rto" makespan_ms="$ms" rtos="$rtos" rto_times="${times:-none}" \
    drops_reported="$drops" vs_100us_ms="$dv" status="$st" \
    note="spurious-RTO probe: raising the floor must remove the firing by construction, so the drop count at the ORIGINAL floor is the test that does not change what it measures"
  printf "  RTO floor %-6s us -> %10s ms (%s vs 100us)  rtos=%-6s times=[%s] drop-lines=%s [%s]\n" \
    "$rto" "$ms" "$dv" "$rtos" "${times:-none}" "$drops" "$st"
}

echo "########## HGX-8 island EP=32, RTO floor probe ##########"
run 100
run 1000
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-160
