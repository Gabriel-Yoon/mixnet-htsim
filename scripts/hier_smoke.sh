#!/bin/bash
# Does -a2a_hier change the flow structure? Flat vs hierarchical on the same
# topology and workload: the banner must switch and total_rounds must differ
# (gather + edge + scatter instead of one flow per pair).
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps
mkdir -p ./pm_logs
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
for mode in flat hier; do
  extra=""; [ "$mode" = hier ] && extra="-a2a_hier"
  log=./pm_logs/hier2_${mode}_${SLURM_JOB_ID:-local}.log
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep32_12_2_1.txt" \
    timeout 600 ./htsim_tcp_glassfb_pm -nodes 256 -flowfile "$R/$L32" \
      -disable-intra-shortcut $extra -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep32.txt" > "$log" 2>&1
  printf "%-6s " "$mode"
  grep -m1 "A2A:" "$log" || echo "  (no A2A banner!)"
  grep -m1 "all2all HIERARCHICAL" "$log" | sed "s/^/       /" || true
  printf "       flat total_rounds: "; grep -m1 "all2all task  total rounds" "$log" | grep -oE "[0-9]+$" || echo "(none)"
  printf "       relayed: "; grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l
done
