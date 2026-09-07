#!/bin/bash
#SBATCH --job-name=calibprobe
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=1:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_calibprobe_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_calibprobe_%j.err

# Build the task-graph generator, then MEASURE what a synthetic all-to-all
# actually puts on the wire before any calibration number is quoted.
#
# Three things are checked rather than derived, because each determines what the
# efficiency figure means:
#
#  1. bytes per ordered pair. load_taskgraph_protobuf reconstructs
#     total_xfer_size = xfersize * ep_degree and then applies the weight matrix.
#     Whether a uniform 8x8 matrix spreads that over 64 entries or over the 56
#     off-diagonal ones decides whether "M per pair" needs total = 56M or 64M.
#     The flow log says which.
#  2. that there are 56 flows, i.e. every ordered pair really starts one.
#  3. that they start together. An all-to-all whose flows are staggered is not
#     the thing the published numbers measure, and the efficiency would be
#     meaningless. GLASS_LOG_FLOWS records each flow as it is sized.
#
# Also checks that a zero-byte combine retires instead of hanging.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO"

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif

echo "########## 1. build gen_decode_block (build only; no model source touched) ##########"
apptainer exec --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO" "$SIF" bash -c '
    set -uo pipefail
    PB=/opt/protobuf-29.0/install
    ABSL=/opt/abseil-cpp-20240722.0/install
    ABSL_LIBS=$(ls $ABSL/lib/libabsl_*.a | sed -e "s#.*/lib#-l#" -e "s#\.a\$##" | tr "\n" " ")
    cd '"$REPO"'/src/clos
    g++ -Wall -std=c++17 -O3 -I. -I./datacenter -I'"$REPO"'/../mixnet-sim/mixnet-flexflow/fbuf/include \
        -I$PB/include -I$ABSL/include \
        gen_decode_block.cpp taskgraph.pb.o \
        -L$PB/lib -Wl,-rpath,$PB/lib -L$ABSL/lib -lprotobuf -lutf8_validity -lutf8_range \
        -Wl,--start-group $ABSL_LIBS -Wl,--end-group \
        -o gen_decode_block
  '
if [ ! -x src/clos/gen_decode_block ]; then
  echo "FATAL: gen_decode_block did not build" >&2; exit 1
fi
echo "built: $(ls -la src/clos/gen_decode_block | awk '{print $5}') bytes"

cd "$REPO/src/clos/datacenter"
mkdir -p calib_logs
T=../../../test

echo
echo "########## 2. uniform 8x8 weight matrix ##########"
python3 ../../../scripts/gen_weightmatrix.py 8 --skew 0 > "$T/wm_calib8.txt"
head -c 120 "$T/wm_calib8.txt"; echo

echo
echo "########## 3. one probe graph: M = 8 MB per ordered pair, total = 56M ##########"
M=8388608
python3 - "$M" > /tmp/calib_probe.json <<'PY'
import json, sys
M = int(sys.argv[1])
json.dump({"ep": 8,
           "total_dispatch_bytes": 56 * M,
           "total_combine_bytes": 0,
           "rank_latency_ns": [0.0] * 8}, sys.stdout)
PY
cat /tmp/calib_probe.json; echo
../gen_decode_block /tmp/calib_probe.json /tmp/calib_probe.pb

echo
echo "########## 4. run it, logging every flow as it is sized ##########"
LD=./logs/calibprobe_${SLURM_JOB_ID}_$$
GLASS_LOG_FLOWS=1 GLASS_RTO_MIN_US=100 timeout 1800 \
  ./htsim_tcp_nvswitch -logdir "$LD" -nodes 8 -flowfile /tmp/calib_probe.pb \
    -nvs_domain 8 -nvs_switches 1 -nvs_link 450 -nvs_lat 250 \
    -nvs_q 2400 -nvs_ecn_k 1200 \
    -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270 -mtu 1500 \
    -weightmatrix "$T/wm_calib8.txt" > ./calib_logs/probe_${SLURM_JOB_ID}.log 2>&1
echo "exit: $?"

L=./calib_logs/probe_${SLURM_JOB_ID}.log
echo
echo "--- banner ---"; grep -m2 -E "NVSwitch model:|NVSwitch queue:" "$L"
echo "--- did it finish an iteration? ---"; grep -m1 "finished one iter" "$L" || echo "  NO COMPLETED ITERATION (a zero-byte combine may be hanging)"
echo "--- flow count and per-pair sizes (the thing being verified) ---"
grep "^flowlog:" "$L" | awk '{print $4}' | sort -n | uniq -c | head
echo "  total flows logged: $(grep -c '^flowlog:' "$L")"
echo "--- simultaneous, or serialized? ---"
# flowlog carries no timestamp (it prints src dst size), so simultaneity is
# checked against the clock instead: with all 56 flows concurrent each GPU sends
# 7M bytes at 450 GB/s, so T_ideal = 7M/450e9. Serialized flows would take about
# seven times that. The ratio T/T_ideal is the discriminator, and it is also the
# efficiency the calibration reports, so this is not a separate assumption.
PS=$(grep "finished one iter" "$L" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
if [ -n "${PS:-}" ]; then
  awk -v ps="$PS" -v m="$M" 'BEGIN{
    T=ps/1e12; ideal=7*m/450e9;
    printf "  T        = %.2f us\n", T*1e6;
    printf "  T_ideal  = %.2f us  (7 x %d B at 450 GB/s)\n", ideal*1e6, m;
    printf "  ratio    = %.2fx   (near 1 = concurrent; near 7 = serialized)\n", T/ideal;
    printf "  egress   = %.1f GB/s -> efficiency %.1f%%\n", 7*m/T/1e9, 100*(7*m/T/1e9)/450;
  }'
else
  echo "  (no completed iteration; nothing to compare)"
fi
echo "--- timeouts ---"
echo "  rtos=$(grep -c '^At ' "$L")"
echo "=== PROBE DONE ==="
