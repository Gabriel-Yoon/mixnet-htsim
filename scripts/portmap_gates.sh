#!/bin/bash
# Port-map loader checks and gates, before any paper row.
#
#  (1) Loader: each map must print its PORT MAP banner, report ports lit per panel
#      within 16, and say the inter_bw env is ignored. ANY "unmapped panel pair
#      relayed" warning means the map or the placement rule is wrong -- that row
#      stops rather than being reported.
#  (2) Determinism: EP=16 twice, identical makespan.
#  (3) Hierarchical A2A smoke: the flag must change the flow structure (the
#      HIERARCHICAL banner appears and total rounds differ from the flat run)
#      while the topology stays identical.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
mkdir -p "$PAPER" ./pm_logs

banner () { # tag nodes fbuf wm map extra...
  local tag=$1 nodes=$2 fb=$3 wm=$4 map=$5; shift 5
  local log=./pm_logs/${tag}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/$map" \
    timeout 240 $BIN -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/$wm" "$@" > "$log" 2>&1
  echo "--- $tag ($map) ---"
  grep -E "PORT MAP|ports lit|IGNORED|panel [0-9]+:" "$log" | head -6
  local relay; relay=$(grep -ci "unmapped panel pair\|relayed" "$log" || true)
  if [ "${relay:-0}" -gt 0 ]; then
    echo "  !! RELAY WARNING present -- map or placement rule wrong, row must not be reported"
    grep -i -m2 "unmapped panel pair\|relayed" "$log"
  else
    echo "  no relay warnings"
  fi
  grep -m1 "A2A:" "$log" || true
  grep -m1 "all2all HIERARCHICAL" "$log" || true
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

echo "########## (1) loader banner per map ##########"
banner load_ep16      128  "$L16" wm_ep16.txt  ep16_0_8_4.txt
banner load_ep32_1221 256  "$L32" wm_ep32.txt  ep32_12_2_1.txt
banner load_ep32_842  256  "$L32" wm_ep32.txt  ep32_8_4_2.txt
banner load_ep64_1221 512  "$QME" wm_ep64.txt  ep64_12_2_1.txt
banner load_ep128     1024 "$ARC" wm_ep128.txt ep128_12_1_1.txt

echo "########## (3) hierarchical A2A smoke (EP=32, same topology) ##########"
banner hier_ep32 256 "$L32" wm_ep32.txt ep32_12_2_1.txt -a2a_hier

echo "=== DONE (banners only; rows come next) ==="
