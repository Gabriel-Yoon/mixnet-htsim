#!/bin/bash
#SBATCH --job-name=glassrate
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=2:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_glassrate_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_glassrate_%j.err

# Does the glass fabric's electrical tier have ZERO transmission time?
#
# Queue::Queue computes _ps_per_byte = (simtime_picosec)(1e12 * 8 / bitrate),
# truncating to an integer. In GB/s that is floor(1000 / rate), so a link is only
# modelled at its stated rate when the rate divides 1000:
#
#   50 GB/s  -> 20 ps/B -> 50      exact   (NVL-64 chip link)
#   112.5    ->  8      -> 125     +11.1%  (HGX-8)
#   450      ->  2      -> 500     +11.1%  (calibration probe, measured 499.5)
#   900      ->  1      -> 1000    +11.1%  (striping control, measured 998.1)
#   384      ->  2      -> 500     +30.2%  (glass optical tier)
#   1800     ->  0      -> infinite        (glass electrical tier)
#
# The NVSwitch side of that table is already measured: 249.9 / 499.5 / 998.1 GB/s
# against stated 225 / 450 / 900, matching floor(1000/rate) exactly at every point.
# This checks the two glass cases on the fabric the paper actually quotes.
#
# If 1800 truncates to zero, then 1800 and 2000 (also -> 0) must produce the SAME
# makespan to the picosecond, while 1000 (-> 1 ps/B, exact) must be slower. That
# is a sharp prediction: a fabric whose links are genuinely faster at 1800 than at
# 1000 would not tie with 2000.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO/src/clos/datacenter"
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps
L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
mkdir -p glassrate_logs

cell () { # elec_bw opt_bw tag
  local elec=$1 opt=$2 tag=$3
  local ld=./logs/glassrate_${SLURM_JOB_ID}_${tag}
  local log=./glassrate_logs/${tag}_${SLURM_JOB_ID}.log
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW="$elec" GLASS_OPT_BW="$opt" \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep16_0_8_4.txt" \
    timeout 3600 ./htsim_tcp_glassfb_pm -logdir "$ld" -nodes 128 -flowfile "$R/$L16" \
      -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/wm_ep16.txt" \
      > "$log" 2>&1
  local ps
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  printf "  elec=%-6s opt=%-5s -> ps_per_byte(elec)=%s  makespan=%s ps (%.3f ms)  rtos=%s\n" \
    "$elec" "$opt" \
    "$(awk -v r="$elec" 'BEGIN{printf "%d", int(1000/r)}')" \
    "${ps:-NONE}" "$(awk -v p="${ps:-0}" 'BEGIN{print p/1e9}')" \
    "$(grep -c '^At ' "$log")"
  grep -m1 "GlassFB distance-layered BW:" "$log" | sed 's/^/      banner: /'
}

echo "########## glass EP=16, quoted config, varying only the electrical tier ##########"
echo "prediction: 1800 and 2000 both truncate to 0 ps/byte and must TIE exactly;"
echo "            1000 gives 1 ps/byte (an honest 1000 GB/s) and must be slower."
cell 1800 384 elec1800
cell 2000 384 elec2000
cell 1000 384 elec1000
echo
echo "########## and the optical tier: 384 (-> 500) against 500 and 250 ##########"
cell 1800 384 opt384
cell 1800 500 opt500
cell 1800 250 opt250
echo "=== GLASS RATE PROBE DONE ==="
