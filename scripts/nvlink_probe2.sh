#!/bin/bash
# (a) PROVE the 1xN grid really gives a full crossbar (degree N-1), not just a
#     label: compare 1x8 against 2x4 at IDENTICAL bandwidth. A real 2x4 FB has
#     degree (2-1)+(4-1)=4, so 3 of 7 peers need a 2-hop relay; 1x8 has degree 7
#     and none do. If the trick works, 1x8 must be strictly faster.
# (b) NVL72 modelled as a 64-GPU domain per MixNet SIGCOMM'25 S8 (they assign 64
#     of 72 to match power-of-2 parallelism), 900 GB/s unidir + 50 GB/s scale-out.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
FB=$R/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb4_H100.fbuf
T=../../../test
mkdir -p ./nvl_logs

probe() {  # label panel pcols elec opt inter
  local label=$1 panel=$2 pcols=$3 elec=$4 opt=$5 inter=$6
  local log=./nvl_logs/${label}_${SLURM_JOB_ID:-local}.log
  env GLASS_PANEL=$panel GLASS_PCOLS=$pcols \
      GLASS_ELEC_BW=$elec GLASS_OPT_BW=$opt GLASS_INTER_BW=$inter \
      GLASS_ELEC_LAT=500 GLASS_OPT_LAT=500 GLASS_INTER_LAT=500 \
      timeout 2400 ./htsim_tcp_glassfb -nodes 128 -flowfile "$FB" \
        -mtu 1500 -q 10000 -weightmatrix $T/wm_ep16.txt > "$log" 2>&1
  local ps
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  echo "=== $label (panel=$panel pcols=$pcols  bw $elec/$opt/$inter) ==="
  grep -m2 "GlassFB 2-tier" "$log" | sed 's/^/  /'
  awk -v p="$ps" 'BEGIN{printf "  makespan: %s ps (%.3f ms)\n", p, p/1e9}'
  echo "  RTOs: $(grep -c '^At ' "$log")"
}

echo "########## (a) crossbar proof: same panel size, same BW, different grid ##########"
probe grid_1x8  8 8  450 450 50
probe grid_2x4  8 4  450 450 50
echo "  ^ if 1x8 is faster at identical BW, the extra links are real (degree 7 vs 4)"

echo "########## (b) NVL72 as a 64-GPU domain (MixNet S8 convention) ##########"
probe nvl5_dom64 64 64 900 900 50
