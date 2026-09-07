#!/bin/bash
# EP128 beyond-domain test: does Glass-FB beat GB200 once the EP group EXCEEDS the NVLink domain?
#
# Workload: qwen3_235B EP=128 on 128 GPUs (dp1 tp1 pp1, 1-layer, seq1024, mb128, H200-measured).
# EP=128 > every domain: GB200 (domain-64) spills half its A2A to the 50 GB/s/GPU NIC tier;
# glass (panel-16) spills 7/8 to its inter-panel edges. The question: can glass win by
# PROVISIONING its passive edges up (fiber headroom: ~650-2600 WG/edge available, ~2 lit;
# +150 GB/s/GPU costs ~3 W/GPU in optics vs ~20 W per extra 800G NIC electrically)?
#
# Runs (all placement-fair, one machine, wm_ep128 seed0, q=10000):
#   glass_design   edge 200 GB/s (= 50 GB/s/GPU egress, same as one 400G NIC)
#   glass_prov800  edge 800 GB/s (= 200 GB/s/GPU, ~+3 W/GPU passive optics)
#   gb200          2 domains x 64 @900 intra, inter = 64 NICs x 50 = 3200 aggregate
#   h100           flat @50 GB/s/GPU (free 8-GPU NVLink islands via ffapp)
#
# RUN ON A COMPUTE NODE (many cores; 4 runs in parallel):
#   nohup bash scripts/ep128_domain_test.sh > outputs/ep128_test.log 2>&1 &
#   tail -f outputs/ep128_test.log
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
ROOT=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim
BIN=$ROOT/mixnet-htsim/src/clos/datacenter
FB=$ROOT/taskgraph_extra/qwen3_235B_dp1tp1pp1_ep128_mb128_1L_seq1024_H200.fbuf
WM=$ROOT/mixnet-htsim/test/wm_ep128.txt
OUT=$ROOT/outputs; mkdir -p "$OUT"
CSV=$OUT/ep128_domain.csv
csv_warn_truncate "$CSV" "fabric,detail,makespan_ps,makespan_ms"
echo "fabric,detail,makespan_ps,makespan_ms" > "$CSV"
cd "$BIN"
[ -s "$WM" ] || python3 $ROOT/scripts/gen_weightmatrix.py 128 > "$WM"
[ -f "$FB" ] || { echo "MISSING $FB"; exit 1; }

run_one(){  # tag cmd... (runs in background caller)
  local tag=$1; shift
  local t0=$SECONDS
  local ps=$("$@" 2>&1 | grep -aoE 'finished one iter.* now [0-9]+' | grep -aoE '[0-9]+$' | tail -1)
  [ -z "$ps" ] && ps=0
  echo "$tag,,$ps,$(awk -v p=$ps 'BEGIN{printf "%.3f",p/1e9}')" >> "$CSV"
  echo "[$tag] $(awk -v p=$ps 'BEGIN{printf "%.1f",p/1e9}') ms (wall $((SECONDS-t0))s)"
}

run_one glass_design  env GLASS_INTER=fb2 GLASS_PANEL=16 GLASS_EP_PLACE=1 GLASS_TP=1 GLASS_EP=128 \
  GLASS_ELEC_BW=1800 GLASS_OPT_BW=400 GLASS_INTER_BW=200 \
  ./htsim_tcp_glassfb -nodes 128 -flowfile "$FB" -q 10000 -weightmatrix "$WM" &
sleep 2
run_one glass_prov800 env GLASS_INTER=fb2 GLASS_PANEL=16 GLASS_EP_PLACE=1 GLASS_TP=1 GLASS_EP=128 \
  GLASS_ELEC_BW=1800 GLASS_OPT_BW=400 GLASS_INTER_BW=800 \
  ./htsim_tcp_glassfb -nodes 128 -flowfile "$FB" -q 10000 -weightmatrix "$WM" &
sleep 2
run_one gb200 env GLASS_PANEL=64 GLASS_EP_PLACE=1 GLASS_TP=1 GLASS_EP=128 \
  GLASS_INTRA_BW=900 GLASS_INTER_BW=3200 \
  ./htsim_tcp_glassfb -nodes 128 -flowfile "$FB" -q 10000 -weightmatrix "$WM" &
sleep 2
run_one h100 ./htsim_tcp_flat -nodes 128 -flowfile "$FB" -speed 400000 -q 10000 -weightmatrix "$WM" &
wait
echo "DONE -> $CSV"; cat "$CSV"
