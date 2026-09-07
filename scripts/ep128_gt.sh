#!/bin/bash
# EP=128 glass (Arctic) on the ground-truth cabling, with the buffer walk built in.
#
# STAGED AHEAD OF ITS MAP. ep128_gt.txt does not exist until fl_ep128 lands and
# the generator is re-run; this script verifies the map covers every used pair
# before it runs anything, so it fails loudly rather than quietly relaying.
#
# The walk starts at 8x, not 4x. At EP=64 the buffer walk went 2x/4x/8x with
# 128k/103k/65k timeouts and never cleared, so starting EP=128 at 4x would spend
# ~40 min learning what EP=64 already told us. If 64x still times out the row is
# reported as "no zero-timeout point in the swept range" -- which at EP=128 is a
# publishable finding about the fabric at that scale, not a gap.
#
# BDP is the inter-panel port's own round trip: 400 GB/s x 2 x 500 ns = 400 kB
# = 267 packets, the same denominator as every other glass row.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
MAP=$PM/ep128_gt.txt
PAIRS=$PM/usedpairs/fl_ep128_arc.pairs
mkdir -p "$PAPER" ./gt128_logs

[ -f "$MAP" ]   || { echo "FATAL: $MAP does not exist yet (needs fl_ep128 + gen_port_map)" >&2; exit 1; }
[ -f "$PAIRS" ] || { echo "FATAL: $PAIRS does not exist yet" >&2; exit 1; }

# Coverage gate BEFORE any run: every used pair must be cabled, or the rows are
# blocked anyway and the hours are wasted discovering it.
python3 - "$PAIRS" "$MAP" <<'PY' || exit 1
import collections, sys
pairs = set()
for ln in open(sys.argv[1]):
    f = ln.split()
    if len(f) >= 2: pairs.add((int(f[0]), int(f[1])))
cab, ports = set(), collections.defaultdict(int)
for ln in open(sys.argv[2]):
    ln = ln.split("#")[0].split()
    if len(ln) < 3: continue
    p, q, n = int(ln[0]), int(ln[1]), int(ln[2])
    cab.add((min(p, q), max(p, q))); ports[p] += n; ports[q] += n
missing = sorted(pairs - cab)
over = {p: n for p, n in ports.items() if n > 16}
print("  coverage: %d used, %d cabled, ports/panel %d..%d" %
      (len(pairs), len(cab), min(ports.values()), max(ports.values())))
if missing: print("  FATAL: %d used pair(s) not cabled: %s" % (len(missing), missing[:8])); sys.exit(1)
if over:    print("  FATAL: panels over 16 ports: %s" % over); sys.exit(1)
print("  coverage OK")
PY

CSV=$PAPER/cliff_ep128_gt.csv
csv_open "$CSV" "paper_ref,system,cabling,model_name,topk,ep,nodes,mb,k,q,q_over_bdp,relayed_pairs,completed,makespan_ms,rtos,ports_lit,wall_s,quotable,status,note"
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf
found=0

run () { # k q
  local k=$1 q=$2
  [ "$found" = 1 ] && return 0
  local log=./gt128_logs/k${k}.log t0 t1
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$MAP" \
    timeout 43200 $BIN -logdir "$(_logdir)" -nodes 1024 -flowfile "$R/$ARC" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep128.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  local relay ps ms rtos ports comp st quot
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  ports=$(grep -m1 "ports lit per panel" "$log" | grep -oE "per panel [0-9]+\.\.[0-9]+" | awk '{print $3}')
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  st=sweep
  if [ "$rc" = "124" ]; then st=truncated; elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked; fi
  quot=no
  if [ "$st" = sweep ] && [ "$rtos" = "0" ]; then quot=yes; found=1; fi
  csv_row "$CSV" paper_ref=cliff system=glassfb cabling=ep128_gt model_name=arctic topk=2 \
    ep=128 nodes=1024 mb=8 k="$k" q="$q" q_over_bdp="$k.0" relayed_pairs="$relay" \
    completed="$comp" makespan_ms="$ms" rtos="$rtos" ports_lit="$ports" wall_s="$((t1-t0))" \
    quotable="$quot" status="$st" \
    note="EP=128 vanishing-timeout walk; started at 8x because EP=64 never cleared at 2x/4x/8x"
  printf "  k=%-3s q=%-6s %-10s relay=%-3s %10s ms rtos=%-8s ports=%-7s wall=%-6ss quotable=%s [%s]\n" \
    "$k" "$q" "$comp" "$relay" "$ms" "$rtos" "$ports" "$((t1-t0))" "$quot" "$st"
}

echo "########## EP=128 Arctic, ground-truth cabling, buffer walk ##########"
run 8 2133
run 16 4267
run 32 8533
run 64 17067
[ "$found" = 0 ] && echo "  NOTE: no zero-timeout point up to 64x BDP -- report as such, do not quote a timing row"
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-155
