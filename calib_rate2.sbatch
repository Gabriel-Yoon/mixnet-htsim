#!/bin/bash
#SBATCH --job-name=calibrat2
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=1:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_calibrat2_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_calibrat2_%j.err

# What rate does one NVSwitch port actually deliver?
#
# The 8-GPU all-to-all probe moved 7 x 58.72 MB per GPU in 0.825 ms = 498 GB/s
# out of a port the banner calls 450 GB/s. About 11% over line rate, which cannot
# be right, so the port rate has to be read directly before any efficiency number
# is quoted.
#
# The first attempt at this aborted on `assert total_row_number==32768` in
# load_weight_matrix: EVERY row of the matrix must sum to 32768. That is the
# constraint the cells below are built around, and it is the reason a source
# cannot simply be zeroed -- each source always sends its share, and the row only
# says how that share is split. A source is therefore silenced by pointing its
# whole row at ITSELF: self-pairs retire immediately without touching a link.
#
#  A. ep=2, rows [[0,32768],[32768,0]] -- exactly one flow per direction, each on
#     its own egress port, nothing sharing. Its rate IS the port rate.
#  B. ep=8, row 0 fanned across 1..7 and rows 1..7 pointed at themselves -- one
#     sender, seven receivers, no other traffic. The aggregate is the per-GPU
#     egress limit the model enforces, isolated from receiver-side incast.
set -uo pipefail
REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$REPO/src/clos/datacenter"
T=../../../test
mkdir -p calib_logs

python3 - > "$T/wm_rate2.txt" <<'PY'
print("[[0,32768],[32768,0]]")
PY

python3 - > "$T/wm_rate8.txt" <<'PY'
n, TOT = 8, 32768
m = [[0] * n for _ in range(n)]
share, rem = TOT // (n - 1), TOT - (TOT // (n - 1)) * (n - 1)
for j in range(1, n):
    m[0][j] = share
m[0][1] += rem                      # rows must sum to exactly 32768
for i in range(1, n):
    m[i][i] = TOT                   # silenced: sends only to itself
assert all(sum(r) == TOT for r in m), [sum(r) for r in m]
print(str(m).replace(" ", ""))
PY
echo "row sums, 8-node fan matrix: $(python3 -c "
import ast;m=ast.literal_eval(open('$T/wm_rate8.txt').read());print([sum(r) for r in m])")"

run () { # tag ep nodes wm total_bytes expect_flows
  local tag=$1 ep=$2 nodes=$3 wm=$4 total=$5
  python3 - "$total" "$ep" > /tmp/rate_$tag.json <<'PY'
import json, sys
print(json.dumps({"ep": int(sys.argv[2]), "total_dispatch_bytes": int(sys.argv[1]),
                  "total_combine_bytes": 0,
                  "rank_latency_ns": [0.0] * int(sys.argv[2])}))
PY
  ../gen_decode_block /tmp/rate_$tag.json /tmp/rate_$tag.pb 2>&1 | tail -1
  local ld=./logs/rate_${SLURM_JOB_ID}_${tag}
  GLASS_RTO_MIN_US=100 timeout 1800 \
    ./htsim_tcp_nvswitch -logdir "$ld" -nodes "$nodes" -flowfile /tmp/rate_$tag.pb \
      -nvs_domain 8 -nvs_switches 1 -nvs_link 450 -nvs_lat 250 \
      -nvs_q 19200 -nvs_ecn_k 9600 \
      -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270 -mtu 1500 \
      -weightmatrix "$T/$wm" > ./calib_logs/${tag}_${SLURM_JOB_ID}.log 2>&1
  echo "  exit=$?  rtos=$(grep -ac '^At ' ./calib_logs/${tag}_${SLURM_JOB_ID}.log)"
  grep -am1 "Assertion" ./calib_logs/${tag}_${SLURM_JOB_ID}.log && return
  awk '/^FCT/ && $4 > 100000 {n++; b+=$4; if($5>mx) mx=$5}
       END{ if(n==0){print "  no payload FCT records"; exit}
            printf "  payload flows=%d  bytes=%d  slowest=%.6f ms  aggregate=%.1f GB/s\n",
                   n, b, mx, b/(mx/1000)/1e9 }' "$ld/fct_util_out.txt"
  awk '/^FCT/ && $4 > 100000 {printf "    %d B in %.6f ms -> %.1f GB/s\n", $4, $5, $4/($5/1000)/1e9}' \
      "$ld/fct_util_out.txt" | sort -u | head -8
}

echo "########## A. ep=2, one flow per direction : the port rate itself ##########"
run two 2 2 wm_rate2.txt $((134217728))

echo
echo "########## B. ep=8, one sender fanning to seven : per-GPU egress limit ##########"
run fan 8 8 wm_rate8.txt $((536870912))

echo
echo "Banner says 450 GB/s per port per direction."
echo "  A above 450  -> the link is provisioned above its stated rate"
echo "  A at 450, B above 450 -> a GPU's flows do not share one egress port"
echo "=== RATE PROBE 2 DONE ==="
