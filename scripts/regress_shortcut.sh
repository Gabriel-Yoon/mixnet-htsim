#!/bin/bash
# Regression gate for commit 1 of the intra-node-shortcut hook.
#
# The hook must be INERT at this commit: with the shortcut ENABLED (both by
# default and by explicit -enable-intra-shortcut) the binary must reproduce the
# pre-patch cliff numbers to the picosecond, and the banner must say ENABLED.
#
# Then, as a preview only, the same two configs with the shortcut DISABLED --
# not a gate, just the first look at how much the bypass was worth.
set -uo pipefail
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PB=../../../experiments/pb_workloads/pb; T=../../../test; RES=../../../experiments/results
mkdir -p "$RES" ./shortcut_logs
CSV=$RES/shortcut_regression.csv
csv_warn_truncate "$CSV" "mode,flag,inter_bw,banner,makespan_ps,makespan_ms,rtos,intra_node_flows,total_flows"
echo "mode,flag,inter_bw,banner,makespan_ps,makespan_ms,rtos,intra_node_flows,total_flows" > "$CSV"

EXPECT_2000=46028299484
EXPECT_2400=6448818088

run() {  # mode flag inter
  local mode=$1 flag=$2 inter=$3
  local log=./shortcut_logs/${mode}_i${inter}.log
  env GLASS_INTER=mesh GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
      GLASS_INTER_BW=$inter GLASS_GW_PARALLEL=4 \
    timeout 4000 ./htsim_tcp_glassfb -nodes 64 -flowfile "$PB/coding_prefill_ep64.pb" \
      $flag -mtu 1500 -q 10000 -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1

  local ps ms rtos banner intra total
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  banner=$(grep -m1 'Intra-node NVLink shortcut:' "$log" | sed 's/.*shortcut: //' | awk '{print $1}')
  [ -z "$banner" ] && banner=MISSING
  # NOTE: the flow_size: line is emitted on the flow-creation path, BEFORE the shortcut
  # test, so these two counts are identical in both modes -- they measure how much
  # traffic is *eligible* for the bypass (a topology fact), not whether it was taken.
  # The banner is the only evidence of which mode ran; makespan is the only evidence of effect.
  total=$(grep -c 'flow_size:' "$log")
  intra=$(grep 'flow_size:' "$log" | awk '{for(i=1;i<=NF;i++){if($i=="src_node:")s=$(i+1); if($i=="dst_node:")d=$(i+1)} if(int(s/8)==int(d/8)) n++} END{print n+0}')
  echo "$mode,${flag:-none},$inter,$banner,$ps,$ms,$rtos,$intra,$total" >> "$CSV"
  printf "  %-22s inter=%-5s banner=%-9s %14s ps (%9s ms)  rtos=%-4s intra_node=%s/%s\n" \
    "$mode" "$inter" "$banner" "$ps" "$ms" "$rtos" "$intra" "$total"
}

echo "########## GATE: shortcut ENABLED must be bit-exact vs pre-patch ##########"
echo "  expect inter=2000 -> $EXPECT_2000 ps ; inter=2400 -> $EXPECT_2400 ps ; banner ENABLED"
run default_on ""                        2000
run default_on ""                        2400
run explicit_on "-enable-intra-shortcut"  2000
run explicit_on "-enable-intra-shortcut"  2400

echo "########## PREVIEW (not a gate): shortcut DISABLED ##########"
run explicit_off "-disable-intra-shortcut" 2000
run explicit_off "-disable-intra-shortcut" 2400

echo "########## VERDICT ##########"
fail=0
while IFS=, read -r mode flag inter banner ps ms rtos intra total; do
  [ "$mode" = "mode" ] && continue
  case "$mode" in
    default_on|explicit_on)
      exp=$EXPECT_2000; [ "$inter" = "2400" ] && exp=$EXPECT_2400
      if [ "$ps" != "$exp" ]; then echo "FAIL $mode/$inter: $ps != $exp"; fail=1
      elif [ "$banner" != "ENABLED" ]; then echo "FAIL $mode/$inter: banner=$banner != ENABLED"; fail=1
      else echo "PASS $mode/$inter: $ps ps, banner ENABLED"; fi
      ;;
    explicit_off)
      [ "$banner" != "DISABLED" ] && { echo "FAIL $mode/$inter: banner=$banner != DISABLED"; fail=1; } \
                                  || echo "ok   $mode/$inter: $ms ms, banner DISABLED, intra_node_flows=$intra/$total"
      ;;
  esac
done < "$CSV"
[ "$fail" = 0 ] && echo "=== GATE PASSED: hook is inert ===" || echo "=== GATE FAILED ==="
cat "$CSV"
