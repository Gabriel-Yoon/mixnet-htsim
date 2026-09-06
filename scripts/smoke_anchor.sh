#!/bin/bash
# GATE 0a: just the EP=64 anchor pair.
#
# The full 8-graph gate (12872799) asks for 256G to accommodate the EP=256
# deepseekR1 row and is stuck at REASON=Priority behind that request. The two
# EP=64 graphs are the comparison anchor and need 64G, the same as every glassfb
# run so far, so they can schedule now instead of waiting on a row we already
# expect not to complete.
#
# Same load-gate semantics as scripts/smoke_training_fbufs.sh: a timeout AFTER
# flows exist is a PASS; a segfault or a zero-flow load is a FAIL.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./smoke_train_logs
CSV=$RES/training_fbuf_smoke_anchor.csv
echo "model,ep,topk,nodes,fbuf_mb,rc,flows,banner,verdict" > "$CSV"

smoke() {  # model ep topk dp tp pp fbuf
  local model=$1 ep=$2 topk=$3 dp=$4 tp=$5 pp=$6 fbuf=$7
  local nodes=$((dp * tp * pp * ep))
  local wm=$T/wm_ep${ep}.txt
  local log=./smoke_train_logs/${model}_ep${ep}.log
  local mb; mb=$(du -m "$R/$fbuf" 2>/dev/null | cut -f1)

  [ -f "$R/$fbuf" ] || { echo "$model,$ep,$topk,$nodes,,-,0,,MISSING_FBUF" >> "$CSV"; echo "  $model FAIL: no fbuf"; return; }
  [ -f "$wm" ]      || { echo "$model,$ep,$topk,$nodes,$mb,-,0,,MISSING_WM"  >> "$CSV"; echo "  $model FAIL: no $wm"; return; }

  GLASS_RTO_MIN_US=1000 GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=640 GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
    timeout 900 ./htsim_tcp_glassfb -nodes "$nodes" -flowfile "$R/$fbuf" \
      -disable-intra-shortcut -mtu 1500 -q 5000 -weightmatrix "$wm" > "$log" 2>&1
  local rc=$? flows banner verdict
  flows=$(grep -c 'flow_size:' "$log")
  banner=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  [ -z "$banner" ] && banner=MISSING
  if [ "$rc" = "139" ] || grep -qi 'segmentation fault' "$log"; then verdict=SEGFAULT
  elif [ "$flows" -eq 0 ]; then verdict=NO_FLOWS
  elif [ "$rc" = "124" ]; then verdict="PASS_load(timeout)"
  elif [ "$rc" = "0" ]; then verdict="PASS_complete"
  else verdict="FAIL_rc$rc"; fi
  echo "$model,$ep,$topk,$nodes,$mb,$rc,$flows,$banner,$verdict" >> "$CSV"
  printf "  %-12s ep=%-4s nodes=%-5s %5sMB rc=%-4s flows=%-8s banner=%-9s %s\n" \
    "$model" "$ep" "$nodes" "$mb" "$rc" "$flows" "$banner" "$verdict"
}

echo "########## EP=64 anchor pair ##########"
smoke qwenMoE   64 4 2 1 4 qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
smoke qwen2_57b 64 8 2 1 4 qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf
echo "########## EP=32 (newly generated -- first load ever) ##########"
smoke llamaMoE32 32 2 2 1 4 llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

echo "=== ANCHOR GATE SUMMARY ==="; cat "$CSV"
awk -F, 'NR>1 && $9 !~ /^PASS/ {print "  BLOCKED: "$1" ep"$2" -> "$9}' "$CSV"
