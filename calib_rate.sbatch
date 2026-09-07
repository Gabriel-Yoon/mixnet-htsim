#!/bin/bash
#SBATCH --job-name=calibrate
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=1:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_calibrate_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_calibrate_%j.err

# What rate does one NVSwitch port actually deliver?
#
# The 8-GPU all-to-all probe moved 7 x 58.72 MB per GPU in 0.825 ms, which is
# 498 GB/s out of a port the banner calls 450 GB/s -- about 11% above line rate,
# which cannot be right. Before any efficiency number is quoted, the port rate
# the model IMPLEMENTS has to be read directly rather than taken from the banner.
#
# Two cells, both on the same 8-GPU S=1 L=450 topology:
#
#  A. ONE flow, 0 -> 1. Its FCT is the port rate with nothing to share it with. If
#     this comes out at 450 GB/s the port is what the banner says and the
#     aggregate anomaly is in how concurrent flows share it. If it comes out near
#     498 the link itself is provisioned above its stated rate.
#
#  B. SEVEN flows, 0 -> {1..7}. One sender, seven receivers, so the sender's
#     egress port is the only possible bottleneck. Aggregate rate here is the
#     per-GPU egress limit the model enforces, isolated from any receiver-side
#     incast.
#
# A and B together separate the three candidate explanations: a mis-stated link
# rate, an egress port that is not shared across a GPU's flows, and a byte
# accounting difference (payload vs wire) that would show up as a fixed ratio.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO/src/clos/datacenter"
T=../../../test
mkdir -p calib_logs

M=67108864          # 64 MB on the wire for the single pair

# weight matrix with a single non-zero entry: only 0 -> 1 carries bytes
python3 - > "$T/wm_calib_one.txt" <<'PY'
n = 8
m = [[0] * n for _ in range(n)]
m[0][1] = 1
print(str(m).replace(" ", ""))
PY

# and one with row 0 fanning out to 1..7, nothing else
python3 - > "$T/wm_calib_fan.txt" <<'PY'
n = 8
m = [[0] * n for _ in range(n)]
for j in range(1, n):
    m[0][j] = 1
print(str(m).replace(" ", ""))
PY

run () { # tag wm total_bytes
  local tag=$1 wm=$2 total=$3
  python3 - "$total" > /tmp/calib_$tag.json <<'PY'
import json, sys
print(json.dumps({"ep": 8, "total_dispatch_bytes": int(sys.argv[1]),
                  "total_combine_bytes": 0, "rank_latency_ns": [0.0] * 8}))
PY
  ../gen_decode_block /tmp/calib_$tag.json /tmp/calib_$tag.pb 2>/dev/null
  local ld=./logs/calibrate_${SLURM_JOB_ID}_${tag}
  GLASS_RTO_MIN_US=100 timeout 1800 \
    ./htsim_tcp_nvswitch -logdir "$ld" -nodes 8 -flowfile /tmp/calib_$tag.pb \
      -nvs_domain 8 -nvs_switches 1 -nvs_link 450 -nvs_lat 250 \
      -nvs_q 9600 -nvs_ecn_k 4800 \
      -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270 -mtu 1500 \
      -weightmatrix "$T/$wm" > ./calib_logs/${tag}_${SLURM_JOB_ID}.log 2>&1
  echo "--- $tag (weightmatrix $wm) ---"
  awk '/^FCT/{n++; b+=$4; if($5>mx) mx=$5} END{
        if(n==0){print "  no FCT records"; exit}
        printf "  flows=%d  bytes=%d  slowest_fct=%.6f ms  aggregate=%.1f GB/s\n", n, b, mx, b/(mx/1000)/1e9
      }' "$ld/fct_util_out.txt"
  awk '/^FCT/ && $4 > 100000 {printf "    flow %d B  %.6f ms  -> %.1f GB/s\n", $4, $5, $4/($5/1000)/1e9}' \
      "$ld/fct_util_out.txt" | head -8
}

echo "########## A. one flow 0->1 : reads the port rate directly ##########"
run one wm_calib_one.txt $((M * 8))

echo
echo "########## B. seven flows 0->1..7 : reads the per-GPU egress limit ##########"
run fan wm_calib_fan.txt $((M * 8))

echo
echo "Stated port rate: 450 GB/s. A should match it; B should not exceed it."
echo "=== RATE PROBE DONE ==="
