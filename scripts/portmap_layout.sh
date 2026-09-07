#!/bin/bash
# Settle the rank layout empirically. Two independent tests:
#
#  (a) pp_major maps, 240 s loader check on EP=16/32. Zero relays would point that
#      way -- but per our own rule a short run proves nothing, so this is only a
#      signal, not a pass.
#  (b) GROUND TRUTH: one COMPLETE EP=16 run with the dp_major map, dumping every
#      unmapped (p,q) pair the workload actually touches, with counts. The set of
#      relayed pairs in hi units (1 hi = ep/psize panels) identifies the layout
#      directly and rules a distance-2 dependency in or out. Only a FULL run with
#      zero relays qualifies a map.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps
BIN=./htsim_tcp_glassfb_pm
mkdir -p ./pm_logs

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf

run () { # tag nodes fbuf wm map timeout
  local tag=$1 nodes=$2 fb=$3 wm=$4 map=$5 tmo=$6
  local log=./pm_logs/${tag}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/$map" \
    timeout "$tmo" $BIN -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/$wm" > "$log" 2>&1
  local rc=$? n ps ms
  n=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  local done_str="COMPLETE"; [ "$rc" = "124" ] && done_str="TRUNCATED(${tmo}s)"
  printf "  %-26s %-16s relayed_pairs=%-3s makespan=%s ms\n" "$tag" "$done_str" "$n" "$ms"
  if [ "$n" -gt 0 ]; then
    echo "      pairs (panel units):"
    grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort | uniq -c | sort -rn | head -12 | sed "s/^/        /"
  fi
}

echo "########## (a) pp_major maps, 240 s signal only ##########"
run ppmaj_ep16       128 "$L16" wm_ep16.txt ep16_0_8_4_ppmajor.txt   240
run ppmaj_ep32_1221  256 "$L32" wm_ep32.txt ep32_12_2_1.txt  240
run ppmaj_ep32_842   256 "$L32" wm_ep32.txt ep32_8_4_2_ppmajor.txt   240

echo "########## (b) GROUND TRUTH: complete EP=16 runs, both layouts ##########"
run truth_ep16_dpmajor 128 "$L16" wm_ep16.txt ep16_0_8_4.txt          3600
run truth_ep16_ppmajor 128 "$L16" wm_ep16.txt ep16_0_8_4_ppmajor.txt  3600

echo "########## hierarchical A2A smoke (flat vs hier, same topology) ##########"
for mode in flat hier; do
  extra=""; [ "$mode" = hier ] && extra="-a2a_hier"
  log=./pm_logs/hiersmoke_${mode}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep32_12_2_1.txt" \
    timeout 300 $BIN -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut $extra -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  printf "  %-6s " "$mode"; grep -m1 "A2A:" "$log" | sed "s/^/ /"
  grep -m1 "all2all HIERARCHICAL" "$log" | sed "s/^/          /" || true
  printf "          first flat total_rounds: "; grep -m1 "all2all task  total rounds" "$log" | grep -oE "[0-9]+$" || echo "(n/a)"
done
echo "=== DONE ==="
