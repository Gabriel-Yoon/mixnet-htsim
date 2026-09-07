#!/bin/bash
# The incumbent's vanishing-timeout buffer at EP=32 and EP=64.
#
# The rule is applied symmetrically or it is not a rule. Glass rows are quoted at
# the shallowest buffer where their timeouts vanish; the packet-level NVL-64 and
# HGX-8 rows currently are not:
#
#   nvl64_pkt ep=32  q=544   159.948 ms   73 RTOs
#   nvl64_pkt ep=64  q=544    86.163 ms 7237 RTOs
#   hgx8_pkt  ep=32  q=1224  164.522 ms  105 RTOs
#   hgx8_pkt  ep=64  q=1224  144.519 ms 2192 RTOs
#
# Only hgx8_pkt at EP=16 (145.497, 0 RTOs) and nvl64_pkt at EP=16 (130.797 at
# 15.6x) currently qualify. Deepening the incumbent's buffer will make it FASTER
# and narrow our margin -- which is exactly why it has to be done rather than
# left. Each cell walks q upward and stops at the first zero-RTO point.
#
# ECN K stays at q/2 so the marking threshold scales with the queue rather than
# becoming a second variable.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./pktvt_logs
CSV=$PAPER/pkt_vanishing_timeout.csv
csv_open "$CSV" "paper_ref,model,model_name,workload_type,system,ep,nodes,domain,switches,link_gbps,nic_bw,q_nvs,q_over_bdp_banner,ecn_k,q_nic,rto_min_us,mtu,makespan_ms,rtos,wall_s,quoted,status,note"

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

cell () { # sys mdl ep nodes fb wm D S L nic qn qc
  local sys=$1 mdl=$2 ep=$3 nodes=$4 fb=$5 wm=$6 D=$7 S=$8 L=$9 nic=${10} qn=${11} qc=${12}
  local log=./pktvt_logs/${SLURM_JOB_ID:-local}_${sys}_ep${ep}_q${qn}.log t0
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 30000 ./htsim_tcp_nvswitch -logdir "$(_logdir)" \
      -nodes "$nodes" -flowfile "$R/$fb" \
      -nvs_domain "$D" -nvs_switches "$S" -nvs_link "$L" -nvs_lat 250 \
      -nvs_q "$qn" -nvs_ecn_k $((qn / 2)) \
      -speed $((nic * 8000)) -rtt 2000 -q "$qc" -port-cap-pkts $((qc / 2)) -mtu 1500 \
      -weightmatrix "$T/$wm" > "$log" 2>&1
  echo "$?:$(($(date +%s)-t0)):$log"
}

sweep () { # sys mdl ep nodes fb wm D S L nic qc q...
  local sys=$1 mdl=$2 ep=$3 nodes=$4 fb=$5 wm=$6 D=$7 S=$8 L=$9 nic=${10} qc=${11}; shift 11
  local qn rc wall log ps ms rtos qob st quoted found=0
  for qn in "$@"; do
    IFS=: read -r rc wall log <<<"$(cell "$sys" "$mdl" "$ep" "$nodes" "$fb" "$wm" "$D" "$S" "$L" "$nic" "$qn" "$qc")"
    ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
    rtos=$(grep -c '^At ' "$log")
    qob=$(grep -m1 "NVSwitch queue" "$log" | grep -oE "\(([0-9.]+)x BDP" | tr -d '(x BDP' || echo "")
    st=sweep
    if   [ "$rc" = "124" ]; then st=truncated
    elif [ "$ps" = "0" ];  then st=no_iteration; fi
    quoted=no
    if [ "$st" = sweep ] && [ "$rtos" = "0" ] && [ "$found" = 0 ]; then quoted=yes; found=1; fi
    csv_row "$CSV" paper_ref=cliff model=pkt model_name="$mdl" workload_type=training \
      system="$sys" ep="$ep" nodes="$nodes" domain="$D" switches="$S" link_gbps="$L" \
      nic_bw="$nic" q_nvs="$qn" q_over_bdp_banner="$qob" ecn_k=$((qn/2)) q_nic="$qc" \
      rto_min_us=100 mtu=1500 makespan_ms="$ms" rtos="$rtos" wall_s="$wall" \
      quoted="$quoted" status="$st" \
      note="incumbent vanishing-timeout sweep; quoted=yes is its shallowest zero-timeout buffer"
    printf "  %-10s ep=%-3s q=%-5s (%sx) -> %10s ms rtos=%-8s wall=%-5ss quoted=%s [%s]\n" \
      "$sys" "$ep" "$qn" "$qob" "$ms" "$rtos" "$wall" "$quoted" "$st"
    [ "$found" = 1 ] && break
  done
  [ "$found" = 0 ] && echo "      NOTE: no zero-timeout point reached for $sys ep=$ep; quote its best and say so"
}

echo "########## NVL-64 packet-level ##########"
sweep nvl64_pkt llamaMoE 32 256 "$L32" wm_ep32.txt 64 18 50 100 540  544 1088 2176 4352
sweep nvl64_pkt qwenMoE  64 512 "$QME" wm_ep64.txt 64 18 50 100 540  544 1088 2176 4352
echo "########## HGX-8 packet-level ##########"
sweep hgx8_pkt  llamaMoE 32 256 "$L32" wm_ep32.txt  8  4 112.5 50 270 1224 2448 4896
sweep hgx8_pkt  qwenMoE  64 512 "$QME" wm_ep64.txt  8  4 112.5 50 270 1224 2448 4896
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-170
