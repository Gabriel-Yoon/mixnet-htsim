#!/bin/bash
# The two missing EP=64 island cells, on qwenMoE top-4.
#
# WHY THESE CELLS. The EP=64 island rows were qwen2_57b top-8 (88.378 NVL-64,
# 493.707 HGX-8) while the glass and packet-level EP=64 cells are qwenMoE top-4,
# so the EP=64 column was not like-for-like. island_cliff.sh and pkt_cliff.sh
# both name the fbuf variable Q64 and point it at DIFFERENT models, which is how
# it went unnoticed. The qwen2_57b rows are kept for the edge study.
#
# WHY THIS IS A REWRITE. The first version appended positionally with
# island_cliff.sh's 36-column HDR. By then fct_recompute.py had added nine
# columns to cliff.csv and the schema change had added model_name, taking the
# file to 46 -- so 36 values went in under a 46-column header, `final` landed
# under the wrong name, and every field after `model` was one place out. Nothing
# errored: a short CSV row is not a parse error, just a row with empty trailing
# fields. csv_row appends BY COLUMN NAME against the file's own header, so
# adding a column later cannot shift a row again, and an unknown key aborts.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./island_logs
CSV=$PAPER/cliff.csv
[ -f "$CSV" ] || { echo "FATAL: $CSV missing; this script appends to it, it does not define it" >&2; exit 1; }

island () { # tag model topk ep nodes fbuf wm sys nic_gbs island_n island_bw q feeder
  local tag=$1 model=$2 topk=$3 ep=$4 nodes=$5 fb=$6 wm=$7 sys=$8 nic=$9 ign=${10} ibw=${11} q=${12} feed=${13}
  # separate statement: bash expands every RHS before local binds any of them
  local log=./island_logs/${tag}_${SLURM_JOB_ID:-local}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 30000 ./htsim_tcp_flat -nodes "$nodes" -flowfile "$R/$fb" \
    -speed $((nic * 8000)) -rtt 2000 -port-cap -port-cap-pkts "$feed" \
    -island_gpus "$ign" -island_bw "$ibw" -mtu 1500 -q "$q" \
    -weightmatrix "$T/$wm" > "$log" 2>&1
  local rc=$?; t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos a2a ld qob st
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  a2a=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  # BDP = NIC rate x RTT, the definition the NVSwitch banner uses
  qob=$(awk -v q="$q" -v n="$nic" 'BEGIN{printf "%.2f", (q*1500)/(n*1e9*2e-6)}')
  # FCT split into payload (> 1 MSS) and all, as elsewhere
  local nt np mean p50 p99 mx mean_a p50_a p99_a mx_a nom
  read -r nt np mean p50 p99 mx mean_a p50_a p99_a mx_a nom <<<"$(awk '
      /^FCT/{n++; v=$5+0; all[n]=v; sa+=v; if($4<=1436){one++} else {m++; p[m]=v; sp+=v}}
      END{ if(n==0){print "0 0 " ; exit}
           asort(all); asort(p);
           printf "%d %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %d",
             n, m, sp/m, p[int(m*0.5)+1], p[int(m*0.99)+1], p[m],
             sa/n, all[int(n*0.5)+1], all[int(n*0.99)+1], all[n], one }' \
      "$ld/fct_util_out.txt" 2>/dev/null)"
  # status derived from the run, never asserted
  st=final
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration; fi

  csv_row "$CSV" \
    paper_ref=cliff workload_type=training ep_source="flexflow_${model}" \
    model=island model_name="$model" topk="$topk" ep="$ep" mb=8 nodes="$nodes" \
    system="$sys" island_gpus="$ign" island_bw="$ibw" nic_bw="$nic" rtt_ns=2000 \
    q="$q" q_over_bdp="$qob" rto_min_us=100 mtu=1500 shortcut_banner=island_analytic \
    makespan_ms="$ms" compute_source=fbuf_cp rtos="$rtos" \
    flows_a2a_only="$a2a" flows_total="${nt:-}" flows_one_mss="${nom:-}" flows_payload="${np:-}" \
    mean_fct_ms="${mean:-}" p50_fct_ms="${p50:-}" p99_fct_ms="${p99:-}" max_fct_ms="${mx:-}" \
    mean_fct_ms_all="${mean_a:-}" p50_fct_ms_all="${p50_a:-}" p99_fct_ms_all="${p99_a:-}" \
    max_fct_ms_all="${mx_a:-}" status_fct=payload_gt_1mss \
    wall_s="$wall" status="$st" \
    note="island analytic scale-up + port-capped non-blocking scale-out (MixNet S7.1); qwenMoE top-4 for like-for-like EP=64"

  printf "  %-22s %-8s ep=%-4s nic=%-4s island=%-3s q=%-5s (%sx BDP) -> %10s ms rtos=%-7s wall=%ss [%s]\n" \
    "$tag" "$sys" "$ep" "$nic" "$ign" "$q" "$qob" "$ms" "$rtos" "$wall" "$st"
}

QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

echo "########## EP=64 island rows on qwenMoE top-4 (like-for-like with glass and pkt) ##########"
island nvl64_ep64_qme qwenMoE 4 64 512 "$QME" wm_ep64.txt nvl64 100 64 900 540 270
island hgx8_ep64_qme  qwenMoE 4 64 512 "$QME" wm_ep64.txt hgx8   50  8 450 270 130
echo "=== DONE ==="
