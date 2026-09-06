#!/bin/bash
# ARM A re-run with the intra-node NVLink shortcut OFF (default as of e2fc399).
#
# THE HYPOTHESIS THIS TESTS. ARM A widens the intra-panel optical width
# (400/512/640/896) with inter held at 200, and every width returned an
# IDENTICAL makespan. At EP=16, 50% of flows shared an 8-GPU block and took the
# shortcut, never touching a waveguide -- so widening the waveguide could not
# move anything. If that was the cause, the degeneracy dissolves here. If the
# widths are still identical with the shortcut off, the flatness is real and
# the intra tier genuinely is not binding.
#
# mb=16 runs FIRST: it is the row most likely to change sign, and results are
# appended as they finish so it can be read before the rest completes.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test
RES=../../../experiments/results
mkdir -p "$RES" ./armA_ns_logs
CSV=$RES/crossover_wg_width_noshortcut.csv
echo "arm,mb,shortcut,inter_mode,opt_bw,inter_bw,gw_parallel,banner,makespan_ps,makespan_ms,rtos" > "$CSV"

run() {  # mb opt flag shortcut_label
  local mb=$1 opt=$2 flag=$3 sc=$4
  local fbuf=$R/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  local log=./armA_ns_logs/armA_mb${mb}_opt${opt}_${sc}.log
  GLASS_INTER=fb2 GLASS_PANEL=16 GLASS_EP_PLACE=1 GLASS_TP=1 GLASS_EP=16 \
  GLASS_ELEC_BW=1800 GLASS_OPT_BW=$opt GLASS_INTER_BW=200 GLASS_GW_PARALLEL=1 \
    timeout 3000 ./htsim_tcp_glassfb -nodes 128 -flowfile "$fbuf" \
      $flag -mtu 1500 -q 10000 -weightmatrix $T/wm_ep16.txt > "$log" 2>&1
  local ps ms rto banner
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rto=$(grep -c '^At ' "$log")
  banner=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  [ -z "$banner" ] && banner=MISSING
  echo "armA,$mb,$sc,fb2,$opt,200,1,$banner,$ps,$ms,$rto" >> "$CSV"
  printf "  mb=%-3s opt=%-4s %-3s banner=%-9s -> %14s ps (%9s ms) rtos=%s\n" \
    "$mb" "$opt" "$sc" "$banner" "$ps" "$ms" "$rto"
}

# mb=16 first, both modes side by side, so the comparison is controlled and early.
echo "########## mb=16 (priority row): shortcut OFF vs ON ##########"
for OPT in 400 512 640 896; do run 16 "$OPT" "-disable-intra-shortcut" off; done
for OPT in 400 512 640 896; do run 16 "$OPT" "-enable-intra-shortcut"  on;  done
echo "--- mb=16 spread check (off) ---"
awk -F, '$2==16 && $3=="off"{print $5, $10}' "$CSV"

echo "########## remaining mb, shortcut OFF ##########"
for MB in 4 8 32; do
  for OPT in 400 512 640 896; do run "$MB" "$OPT" "-disable-intra-shortcut" off; done
done

echo "=== DONE rows: $(($(wc -l < "$CSV") - 1)) ==="
cat "$CSV"
