#!/bin/bash
# Hierarchical A2A gates. Built long ago, deadlock fixed, never gated.
#
# G1 byte conservation: the hierarchical plan must move the SAME bytes across
#    each panel edge as the flat all-to-all. It restructures flows (gather ->
#    one flow per gateway -> scatter), so per-flow endpoints differ by design;
#    what must not differ is the cross-panel byte total per panel pair.
# G2 inert in-panel: at EP=16 the expert group is one panel, so there is nothing
#    to aggregate and the flag must change NOTHING -- bit-identical to 86.750.
# G3 EP=32 on the corrected cabling at its quoted buffer, vs 75.542 / 0 RTO.
# G4 EP=64 on ep64_gt at q=1064, vs 52.004 / 102601 RTO.
#
# This decides whether the paper gets a gateway-aggregated result or a sentence
# saying it did not help once the cabling was right. Either is publishable; a
# silent omission is not.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pmhop        # has the zero-byte retirement fix and both logs
mkdir -p "$PAPER" ./hier_logs
CSV=$PAPER/hier_gates.csv
csv_open "$CSV" "paper_ref,system,cabling,ep,nodes,mb,q,a2a_mode,relayed_pairs,completed,makespan_ms,rtos,max_fct_payload_ms,cross_panel_TB,vs_flat_ms,vs_flat_pct,wall_s,quotable,status,note"

cell () { # tag nodes fbuf wm map q mode(flat|hier) ref_ms
  local tag=$1 nodes=$2 fb=$3 wm=$4 map=$5 q=$6 mode=$7 ref=$8
  local log=./hier_logs/${tag}_${SLURM_JOB_ID:-local}.log t0 extra=""
  [ "$mode" = hier ] && extra="-a2a_hier"
  t0=$(date +%s)
  GLASS_LOG_FLOWS=1 GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/$map" \
    timeout 30000 $BIN -logdir "$(_logdir)" -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut $extra -mtu 1500 -q "$q" -weightmatrix "$T/$wm" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  grep "^flowlog: " "$log" > ./hier_logs/${tag}.flowlog
  local relay ps ms rtos comp st mx xtb dv dp
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  local ld; ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  mx=$(awk '/^FCT/{if($4>1436 && $5+0>m) m=$5+0} END{printf "%.4f", m}' "$ld/fct_util_out.txt" 2>/dev/null || echo "")
  # cross-panel bytes: the G1 quantity, from the flow log
  xtb=$(awk '{p=int($2/16); q2=int($3/16); if(p!=q2) s+=$4} END{printf "%.6f", s/1e12}' ./hier_logs/${tag}.flowlog)
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=gate
  if [ "$rc" = "124" ]; then st=truncated; elif [ "$ps" = "0" ]; then st=no_iteration; fi
  dv=""; dp=""
  if [ "$ref" != "-" ] && [ "$ps" != "0" ]; then
    dv=$(awk -v a="$ms" -v b="$ref" 'BEGIN{printf "%+.3f", a-b}')
    dp=$(awk -v a="$ms" -v b="$ref" 'BEGIN{printf "%+.2f", 100*(a-b)/b}')
  fi
  local quot=no
  [ "$st" = gate ] && [ "$relay" = 0 ] && [ "$rtos" = 0 ] && quot=yes
  csv_row "$CSV" paper_ref=hier system="glassfb_$mode" cabling="$map" ep="$9" nodes="$nodes" mb=8 \
    q="$q" a2a_mode="$mode" relayed_pairs="$relay" completed="$comp" makespan_ms="$ms" rtos="$rtos" \
    max_fct_payload_ms="$mx" cross_panel_TB="$xtb" vs_flat_ms="$dv" vs_flat_pct="$dp" \
    wall_s="$((t1-t0))" quotable="$quot" status="$st" \
    note="hierarchical A2A gate; cross_panel_TB is the G1 conservation quantity and must match the flat run"
  printf "  %-18s %-5s q=%-5s %-10s relay=%-3s %10s ms rtos=%-8s xTB=%-10s %s%s [%s]\n" \
    "$tag" "$mode" "$q" "$comp" "$relay" "$ms" "$rtos" "$xtb" "${dv:+vs flat }" "${dp:+$dp%}" "$st"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

echo "########## G2: EP=16, the flag must be inert (expert group is one panel) ##########"
cell g2_ep16_flat 128 "$L16" wm_ep16.txt ep16_0_8_4.txt 1064 flat -    16
cell g2_ep16_hier 128 "$L16" wm_ep16.txt ep16_0_8_4.txt 1064 hier 86.750 16
echo "########## G1+G3: EP=32 at its quoted buffer ##########"
cell g3_ep32_flat 256 "$L32" wm_ep32.txt ep32_gt.txt   2133 flat -    32
cell g3_ep32_hier 256 "$L32" wm_ep32.txt ep32_gt.txt   2133 hier 75.542 32
echo "########## G4: EP=64 at q=1064, against the relay-clean reference ##########"
cell g4_ep64_flat 512 "$QME" wm_ep64.txt ep64_gt.txt   1064 flat -    64
cell g4_ep64_hier 512 "$QME" wm_ep64.txt ep64_gt.txt   1064 hier 52.004 64
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-165
