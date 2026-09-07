#!/bin/bash
# STRIPING CONTROL for NVSwitch: S=1, L=900 GB/s.
#
# THE QUESTION. Is the incumbent's 82.5 ms at EP=64 a property of incast, or an
# artefact of how this model routes? Our NVSwitch model pins each flow to one of
# S=18 chip links by per-flow ECMP, so a single transfer gets 50 GB/s. Real NVLink
# stripes one transfer across all 18. If the makespan is set by striping bandwidth
# rather than by contention at the destination, the incumbent is being modelled
# unfairly and the 2.09x gap is partly ours.
#
# THE CONTROL. One 900 GB/s up/down link per GPU instead of eighteen 50 GB/s ones:
# same binary, same D=64 domain, same 250 ns hop, same NIC tier. Every flow now
# sees the full 900 GB/s a striped transfer would, while the destination's
# down-link is still a single queue -- so incast is preserved exactly and only the
# per-flow bandwidth limit is removed.
#
# This is a striping UPPER BOUND, not a replacement for the S=18 rows. Real
# striping splits a transfer across links that other transfers also share; this
# gives every flow the whole pipe. If the makespan barely moves, per-flow pinning
# was not the limit and incast is. If it collapses, it was.
#
# BDP. The port BDP changes with the link, so the walk is in multiples of the NEW
# one: 900 GB/s x 4 x 250 ns = 900 kB = 600 full-MTU packets at 1x. The rungs are
# 2x 4x 8x 16x 32x 64x of that, and ECN K stays at half the queue. The banner
# prints what the topology actually used; that is the number to trust, not this
# arithmetic.
#
# The _drop build is used throughout rather than only on the quoted rung. It is
# the same simulator plus counters -- it reproduced 86.750, 75.542 and 119.397 to
# the digit against the uninstrumented build -- so every rung gets a measured drop
# count for free, and a zero means no loss rather than no counting.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_nvswitch_drop
mkdir -p "$PAPER" ./stripe_logs
[ -x "$BIN" ] || { echo "FATAL: $BIN missing" >&2; exit 1; }
[ "$(strings "$BIN" 2>/dev/null | grep -c dropcount)" -ge 1 ] \
  || { echo "FATAL: $BIN has no drop counter -- wrong binary" >&2; exit 1; }

CSV=$PAPER/cliff_pkt_stripe.csv
csv_open "$CSV" "paper_ref,model,workload_type,ep_source,model_name,topk,ep,mb,nodes,system,domain,switches,link_gbps,nvs_lat_ns,nic_bw,rtt_ns,q_nvs,q_over_bdp_4lat,q_nic,rto_min_us,mtu,makespan_ms,rtos,drops,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,max_fct_ms,banner_q_pkt,banner_ecn_k,wall_s,status,note,quotable,quotable_why"

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

# one 900 GB/s port, 4 x 250 ns round trip -> 900 kB -> 600 pkt at 1500 B
BDP_PKT=600

sweep () { # model_name topk ep nodes fbuf wm q_nic  q...
  local mdl=$1 topk=$2 ep=$3 nodes=$4 fb=$5 wm=$6 qc=$7; shift 7
  local qn ld log t0 t1 rc ps ms rtos drops st quot found=0
  local bq bk s
  echo "########## S=1 L=900 striping control -- EP=$ep $mdl ##########"
  for qn in "$@"; do
    ld=$(_logdir)                       # ONCE: run writes here, tail is read here
    log=./stripe_logs/${SLURM_JOB_ID:-local}_ep${ep}_q${qn}.log
    t0=$(date +%s)
    GLASS_RTO_MIN_US=100 timeout 30000 $BIN -logdir "$ld" \
        -nodes "$nodes" -flowfile "$R/$fb" \
        -nvs_domain 64 -nvs_switches 1 -nvs_link 900 -nvs_lat 250 \
        -nvs_q "$qn" -nvs_ecn_k $((qn / 2)) \
        -speed 800000 -rtt 2000 -q "$qc" -port-cap-pkts $((qc / 2)) -mtu 1500 \
        -weightmatrix "$T/$wm" > "$log" 2>&1
    rc=$?; t1=$(date +%s)

    ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
    rtos=$(grep -c '^At ' "$log")
    drops=$(grep -m1 -oE "dropcount: [0-9]+" "$log" | awk '{print $2}')
    bq=$(grep -m1 -oE "NVSwitch queue: [0-9]+ pkt" "$log" | awk '{print $3}')
    bk=$(grep -m1 -oE "ECN K [0-9]+ pkt" "$log" | awk '{print $3}')
    grep -m1 "NVSwitch queue:" "$log" | sed 's/^/      banner: /'

    st=sweep
    if [ "$rc" = "124" ]; then st=truncated; elif [ "$ps" = "0" ]; then st=no_iteration; fi
    quot=no
    if [ "$st" = sweep ] && [ "$rtos" = "0" ]; then quot=yes; found=1; fi

    s=$(awk '/^FCT/{n++; v=$5+0; if($4>1436){m++; p[m]=v; s+=v}}
         END{if(m==0){print "0,0,,,,"; exit} asort(p);
             printf "%d,%d,%.4f,%.4f,%.4f,%.4f", n, m, s/m, p[int(m*0.5)+1], p[int(m*0.99)+1], p[m]}' \
        "$ld/fct_util_out.txt" 2>/dev/null || echo "0,0,,,,")

    csv_row "$CSV" paper_ref=cliff model=pkt workload_type=training \
      ep_source=flexflow_stripe_control model_name="$mdl" topk="$topk" ep="$ep" mb=8 \
      nodes="$nodes" system=nvl64_pkt_s1 domain=64 switches=1 link_gbps=900 \
      nvs_lat_ns=250 nic_bw=100 rtt_ns=2000 q_nvs="$qn" \
      q_over_bdp_4lat="$(awk -v q="$qn" -v b="$BDP_PKT" 'BEGIN{printf "%.2f", q/b}')" \
      q_nic="$qc" rto_min_us=100 mtu=1500 makespan_ms="$ms" rtos="$rtos" \
      drops="${drops:-}" \
      flows_total="$(echo "$s" | cut -d, -f1)" flows_payload="$(echo "$s" | cut -d, -f2)" \
      mean_fct_ms="$(echo "$s" | cut -d, -f3)" p50_fct_ms="$(echo "$s" | cut -d, -f4)" \
      p99_fct_ms="$(echo "$s" | cut -d, -f5)" max_fct_ms="$(echo "$s" | cut -d, -f6)" \
      banner_q_pkt="${bq:-}" banner_ecn_k="${bk:-}" \
      wall_s="$((t1-t0))" status="$st" quotable="$quot" \
      note="striping control S=1 L=900; one 900 GB/s port per GPU; incast preserved; upper bound on striping"

    printf "  ep=%-4s q=%-6s (%sx) %10s ms rtos=%-8s drops=%-9s maxFCT=%-9s wall=%-6ss quotable=%s [%s]\n" \
      "$ep" "$qn" "$(awk -v q="$qn" -v b="$BDP_PKT" 'BEGIN{printf "%.1f", q/b}')" \
      "$ms" "$rtos" "${drops:-?}" "$(echo "$s" | cut -d, -f6)" "$((t1-t0))" "$quot" "$st"

    [ "$found" = 1 ] && break
  done
  [ "$found" = 0 ] && echo "      NOTE: no zero-timeout rung for EP=$ep in 2x..64x -- report as such; do not quote a timing row"
}

# The disputed cell first, so the answer arrives before the other two.
sweep qwenMoE  4 64 512 "$QME" wm_ep64.txt 540  1200 2400 4800 9600 19200 38400
sweep llamaMoE 2 32 256 "$L32" wm_ep32.txt 540  1200 2400 4800 9600 19200 38400
sweep llamaMoE 2 16 128 "$L16" wm_ep16.txt 540  1200 2400 4800 9600 19200 38400
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-200
