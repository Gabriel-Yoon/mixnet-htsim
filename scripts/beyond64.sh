#!/bin/bash
# The regime where the thesis actually lives: past every system's domain boundary.
#
# THE SHAPE OF THE PROBLEM. flat@900 got FASTER from EP=16 to EP=32 (86.5 -> 67.8
# ms: more GPUs, less compute each, no boundary to pay) while glass got 2.15x
# SLOWER (86.7 -> 186.4) because 32 crosses its 16-GPU panel boundary. Every
# system pays at its own boundary; glass's is at 16, NVL72's is at 64. So at
# EP <= 64 we compare a fabric past its boundary against one inside its boundary,
# and losing is the expected outcome, not a finding.
#
# (A) Does provisioning rescue glass at EP=32 in TRAINING? Unlike the inference
#     corner -- where every cell sat at 187-3776 RTOs and inter bandwidth bought
#     under 7% -- the training rows are at 0 RTO, i.e. bandwidth-bound rather than
#     timeout-bound. Provisioning may therefore actually matter here. If inter
#     3200 closes much of the 2.75x, that is a training-relevant provisioning
#     result; if it does not, the loss is topological (2 hops + relay) and we say
#     so plainly.
#
# (B) EP > 64, where NVL72 falls to its 100 GB/s scale-out tier and glass keeps
#     optical edges. Only affordable in inference (an EP=128 training cell is
#     2.5-5 h). The dom64 config's in-domain mismodel is second-order here because
#     the result is dominated by the inter-domain tier -- the same argument that
#     makes dom8 usable -- but that caveat must be stated wherever these rows are
#     reported. flat cannot serve this regime at all: it has no domain boundary.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./beyond64_logs
CSV=$RES/beyond64.csv
echo "arm,workload_type,ep_source,workload,ep,nodes,system,panel,elec_bw,opt_bw,inter_bw,G,shortcut,makespan_ps,makespan_ms,rtos,wall_s" > "$CSV"

cell() { # arm wtype src wl ep nodes flowfile wm system panel elec opt inter G scflag tag
  local arm=$1 wt=$2 src=$3 wl=$4 ep=$5 nodes=$6 ff=$7 wm=$8 sys=$9 panel=${10} elec=${11} opt=${12} inter=${13} g=${14} sc=${15} tag=${16}
  local log=./beyond64_logs/${tag}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_INTER=mesh GLASS_PANEL=$panel GLASS_ELEC_BW=$elec \
  GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=$g \
    timeout 25200 ./htsim_tcp_glassfb -nodes "$nodes" -flowfile "$ff" \
      $sc -mtu 1500 -q 5000 -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos scb
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  scb=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  echo "$arm,$wt,$src,$wl,$ep,$nodes,$sys,$panel,$elec,$opt,$inter,$g,$scb,$ps,$ms,$rtos,$wall" >> "$CSV"
  printf "  %-14s %-16s ep=%-4s %-12s inter=%-5s %11s ms rtos=%-6s wall=%ss\n" \
    "$arm" "$wl" "$ep" "$sys" "$inter" "$ms" "$rtos" "$wall"
}

L32=$R/llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

echo "########## (A) TRAINING EP=32: does inter provisioning rescue glass? ##########"
echo "   baseline at inter 1600 was 186.383 ms / 0 RTO; flat@900 was 67.821 ms"
cell provision training flexflow_llamaMoE llamaMoE 32 256 "$L32" wm_ep32.txt glassfb_mesh 16 1800 384 3200 4 "-disable-intra-shortcut" tr32_i3200
cell provision training flexflow_llamaMoE llamaMoE 32 256 "$L32" wm_ep32.txt glassfb_mesh 16 1800 640 3200 4 "-disable-intra-shortcut" tr32_i3200_o640

echo "########## (B) INFERENCE EP>64 at derived transport, the beyond-boundary regime ##########"
for ep in 128 144; do
  for wl in coding_prefill agentic_prefill; do
    f="$PB/${wl}_ep${ep}.pb"
    [ -f "$f" ] || { echo "  skip: no $f"; continue; }
    cell beyond64 inference llmservingsim_deepseekv3_1layer "$wl" "$ep" "$ep" "$f" wm_ep${ep}.txt glassfb_mesh 16 1800 384 1600 4 "-disable-intra-shortcut" inf${ep}_${wl}_glass
    cell beyond64 inference llmservingsim_deepseekv3_1layer "$wl" "$ep" "$ep" "$f" wm_ep${ep}.txt nvl5_dom64 64 900 900 100 1 "-enable-intra-shortcut" inf${ep}_${wl}_dom64
    cell beyond64 inference llmservingsim_deepseekv3_1layer "$wl" "$ep" "$ep" "$f" wm_ep${ep}.txt nvl4_dom8   8 450 450  50 1 "-enable-intra-shortcut" inf${ep}_${wl}_dom8
  done
done

echo "=== DONE ==="; cat "$CSV"
