#!/bin/bash
# GATE 0 (D34): does each EP>=32 training fbuf actually LOAD in the patched binary?
#
# Nothing downstream counts until this passes. Precedent: the Mixtral fbuf
# segfaulted because ffapp.cpp calls ->str() on an omitted FlatBuffers field, and
# it did so only at load time -- a file that exists and has a plausible size is
# not evidence that it can be read.
#
# This is a LOAD test, not a performance run: a short timeout is expected and a
# timeout AFTER flows have been created counts as a PASS. What fails is a
# segfault, a zero-flow load, or a missing weight matrix.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./smoke_train_logs
CSV=$RES/training_fbuf_smoke.csv
echo "model,ep,topk,dp,tp,pp,nodes,fbuf_mb,wm,rc,flows,banner,verdict" > "$CSV"

smoke() {  # model ep topk dp tp pp fbuf
  local model=$1 ep=$2 topk=$3 dp=$4 tp=$5 pp=$6 fbuf=$7
  local nodes=$((dp * tp * pp * ep))
  local wm=$T/wm_ep${ep}.txt
  local log=./smoke_train_logs/${model}_ep${ep}.log
  local mb=$(du -m "$R/$fbuf" 2>/dev/null | cut -f1)

  if [ ! -f "$R/$fbuf" ]; then
    echo "$model,$ep,$topk,$dp,$tp,$pp,$nodes,,,-,0,,MISSING_FBUF" >> "$CSV"
    printf "  %-12s ep=%-4s FAIL: fbuf not found\n" "$model" "$ep"; return
  fi
  if [ ! -f "$wm" ]; then
    echo "$model,$ep,$topk,$dp,$tp,$pp,$nodes,$mb,MISSING,-,0,,MISSING_WM" >> "$CSV"
    printf "  %-12s ep=%-4s FAIL: no %s\n" "$model" "$ep" "$wm"; return
  fi

  GLASS_RTO_MIN_US=1000 GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=640 GLASS_INTER_BW=1600 GLASS_GW_PARALLEL=4 \
    timeout 900 ./htsim_tcp_glassfb -nodes "$nodes" -flowfile "$R/$fbuf" \
      -disable-intra-shortcut -mtu 1500 -q 5000 -weightmatrix "$wm" > "$log" 2>&1
  local rc=$?

  local flows banner verdict
  flows=$(grep -c 'flow_size:' "$log")
  banner=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  [ -z "$banner" ] && banner=MISSING

  # 124 = timeout. A timeout with flows already created means the graph loaded fine.
  if [ "$rc" = "139" ] || grep -qi 'segmentation fault' "$log"; then verdict=SEGFAULT
  elif [ "$flows" -eq 0 ]; then verdict=NO_FLOWS
  elif [ "$rc" = "124" ]; then verdict="PASS_load(timeout)"
  elif [ "$rc" = "0" ]; then verdict="PASS_complete"
  else verdict="FAIL_rc$rc"; fi

  echo "$model,$ep,$topk,$dp,$tp,$pp,$nodes,$mb,ok,$rc,$flows,$banner,$verdict" >> "$CSV"
  printf "  %-12s ep=%-4s nodes=%-5s %5sMB rc=%-4s flows=%-7s banner=%-9s %s\n" \
    "$model" "$ep" "$nodes" "$mb" "$rc" "$flows" "$banner" "$verdict"
}

echo "########## EP=64 (the comparison anchor) ##########"
smoke qwenMoE   64  4 2 1 4 qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
smoke qwen2_57b 64  8 2 1 4 qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf

echo "########## EP=128 ##########"
smoke arctic     128 2 2 1 4 arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf
smoke qwen3_235b 128 8 2 1 4 qwen3_235b_paper_dp2tp1pp4_ep128top8_L4_seq1024_mb8_H100.fbuf

echo "########## EP=160 ##########"
smoke deepseekv2 160 6 2 1 4 deepseekv2_paper_dp2tp1pp4_ep160top6_L4_seq1024_mb8_H100.fbuf

echo "########## EP=64 extra sequence/layer variants ##########"
smoke qwenMoE_s4k  64 4 2 1 4 qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq4096_mb8_H100.fbuf
smoke qwenMoE_L24  64 4 2 1 4 qwenMoE_paper_dp2tp1pp4_ep64top4_L24_seq4096_mb8_H100.fbuf

echo "########## EP=256 stretch row (2.06 GB, pp16 -> 8192 nodes) ##########"
smoke deepseekR1 256 8 2 1 16 deepseekR1_paper_dp2tp1pp16_ep256top8_L16_seq4096_mb8_H100.fbuf

echo "=== GATE SUMMARY ==="
cat "$CSV"
echo
awk -F, 'NR>1 && $13 !~ /^PASS/ {print "  BLOCKED: "$1" ep"$2" -> "$13}' "$CSV"
