#!/bin/bash
# The island rows' own vanishing-timeout walk, on the NIC tier.
#
# One rule everywhere. The HGX-8 island rows at EP=32 (105 RTO) and EP=64
# (15 900 RTO) fail the vanishing-timeout rule, so the dashed bound is a single
# point. The island's scale-up half has no queue by construction -- it is
# completed analytically -- but its scale-out half is a real port-capped TCP
# fabric with a real buffer, and that is where the timeouts are. So the rule
# applies to it exactly as to everything else, and the walk is on q (and the
# port feeder, kept at q/2 as elsewhere).
#
# Writes its own CSV rather than appending to cliff.csv: that file is written
# positionally by island_cliff.sh against a 36-column header and has since grown
# to 46 columns, which is the shift that corrupted two rows earlier.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./islvt_logs
CSV=$PAPER/island_vanishing_timeout.csv
csv_open "$CSV" "paper_ref,model,system,model_name,topk,ep,mb,nodes,island_gpus,island_bw,nic_bw,rtt_ns,q,q_over_bdp,feeder_pkts,rto_min_us,mtu,makespan_ms,rtos,wall_s,quoted,status,note"

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

sweep () { # sys model topk ep nodes fb wm nic ign ibw q...
  local sys=$1 mdl=$2 topk=$3 ep=$4 nodes=$5 fb=$6 wm=$7 nic=$8 ign=$9 ibw=${10}; shift 10
  local q feed log t0 t1 rc ps ms rtos qob st quoted found=0
  for q in "$@"; do
    feed=$((q / 2))
    log=./islvt_logs/${sys}_ep${ep}_q${q}.log
    t0=$(date +%s)
    GLASS_RTO_MIN_US=100 timeout 30000 ./htsim_tcp_flat -logdir "$(_logdir)" \
      -nodes "$nodes" -flowfile "$R/$fb" \
      -speed $((nic * 8000)) -rtt 2000 -port-cap -port-cap-pkts "$feed" \
      -island_gpus "$ign" -island_bw "$ibw" -mtu 1500 -q "$q" \
      -weightmatrix "$T/$wm" > "$log" 2>&1
    rc=$?; t1=$(date +%s)
    ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
    rtos=$(grep -c '^At ' "$log")
    qob=$(awk -v q="$q" -v n="$nic" 'BEGIN{printf "%.2f", (q*1500)/(n*1e9*2e-6)}')
    st=sweep
    if [ "$rc" = "124" ]; then st=truncated; elif [ "$ps" = "0" ]; then st=no_iteration; fi
    quoted=no
    if [ "$st" = sweep ] && [ "$rtos" = "0" ] && [ "$found" = 0 ]; then quoted=yes; found=1; fi
    csv_row "$CSV" paper_ref=cliff model=island system="$sys" model_name="$mdl" topk="$topk" \
      ep="$ep" mb=8 nodes="$nodes" island_gpus="$ign" island_bw="$ibw" nic_bw="$nic" rtt_ns=2000 \
      q="$q" q_over_bdp="$qob" feeder_pkts="$feed" rto_min_us=100 mtu=1500 \
      makespan_ms="$ms" rtos="$rtos" wall_s="$((t1-t0))" quoted="$quoted" status="$st" \
      note="island vanishing-timeout walk on the NIC tier; the scale-up half is analytic and has no queue, the scale-out half does"
    printf "  %-7s ep=%-3s q=%-5s (%sx BDP) feeder=%-5s -> %10s ms rtos=%-7s quoted=%s [%s]\n" \
      "$sys" "$ep" "$q" "$qob" "$feed" "$ms" "$rtos" "$quoted" "$st"
    [ "$found" = 1 ] && break
  done
  [ "$found" = 0 ] && echo "      NOTE: no zero-timeout point for $sys ep=$ep in the swept range"
}

echo "########## HGX-8 island, the two cells that fail the rule ##########"
sweep hgx8 llamaMoE 2 32 256 "$L32" wm_ep32.txt 50 8 450  270 540 1080 2160
sweep hgx8 qwenMoE  4 64 512 "$QME" wm_ep64.txt 50 8 450  270 540 1080 2160
echo "########## NVL-64 island at the same EP, for a matched bound ##########"
sweep nvl64 llamaMoE 2 32 256 "$L32" wm_ep32.txt 100 64 900  540 1080 2160
sweep nvl64 qwenMoE  4 64 512 "$QME" wm_ep64.txt 100 64 900  540 1080 2160
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-160
