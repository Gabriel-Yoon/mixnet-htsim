#!/bin/bash
# Can an NVLink scale-up domain be expressed on the existing GlassFBTopology
# with no code change? Requires: intra-domain FULL crossbar, uniform rate,
# slow inter-domain tier, no EP-aware placement.
#
# Trick: intra_link() = same panel && (same row || same col). With a 1xN grid
# (GLASS_PCOLS = GLASS_PANEL) every GPU is in row 0, so every intra-domain pair
# is directly linked -> full crossbar. Setting ELEC_BW == OPT_BW makes the rate
# uniform regardless of grid distance.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
FB=$R/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb4_H100.fbuf
T=../../../test
mkdir -p ./nvl_logs

probe() {  # label panel pcols elec opt inter extra_env
  local label=$1 panel=$2 pcols=$3 elec=$4 opt=$5 inter=$6
  local log=./nvl_logs/${label}.log
  env GLASS_PANEL=$panel GLASS_PCOLS=$pcols \
      GLASS_ELEC_BW=$elec GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter \
      GLASS_ELEC_LAT=500 GLASS_OPT_LAT=500 GLASS_INTER_LAT=500 \
      timeout 1500 ./htsim_tcp_glassfb -nodes 128 -flowfile "$FB" \
        -mtu 1500 -q 10000 -weightmatrix $T/wm_ep16.txt > "$log" 2>&1
  echo "=== $label (panel=$panel pcols=$pcols elec=$elec opt=$opt inter=$inter) ==="
  grep -m3 "GlassFB 2-tier\|distance-layered BW\|EP-aware" "$log"
  local ps
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  awk -v p="$ps" 'BEGIN{printf "  makespan: %s ps (%.3f ms)\n", p, p/1e9}'
  echo "  RTOs: $(grep -c '^At ' "$log")"
}

# NVLink4 / HGX-8: 8-GPU domain, full crossbar at 450 GB/s unidir, IB 50 beyond
probe nvl4_dom8   8  8  450 450 50
# NVLink5 / NVL72 rate on the same 8-domain shape, for rate sensitivity
probe nvl5_rate   8  8  900 900 50
# Glass-FB reference at the published design, same workload
probe glassfb_ref 16 4  1800 400 200
