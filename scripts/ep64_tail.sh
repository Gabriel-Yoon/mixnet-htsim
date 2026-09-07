#!/bin/bash
# Glass EP=64 FCT tails at the two buffers R4 is missing: 32x and 64x.
#
# WHY A RE-RUN RATHER THAN A READ. The walk that produced 39.410 and 39.395 wrote
# all three of its cells into ONE output directory: _logdir incremented a counter
# inside $(_logdir)'s subshell, so the increment never reached the parent and the
# name never changed. Makespan and RTO counts survived that -- they are parsed
# from stdout -- but the FCT file cannot be attributed to a cell, which is why
# mark_fct_status marks those rows shared_logdir and buffer_sweeps leaves their
# max_fct_ms blank. The tails are not recoverable from the existing logs, so they
# are measured again.
#
# TWO GUARDS.
#
# 1. ld is taken ONCE per cell and used for both -logdir and the FCT read, and
#    _logdir is now nanosecond-unique (fbcece7), so each cell owns its directory.
#    The read also happens immediately after its own cell, which is the property
#    that kept nvl16_clean's tails correct even under the broken counter.
#
# 2. Each cell must reproduce the makespan the walk measured, to the picosecond.
#    A tail is only meaningful for the row it belongs to, and these rows are
#    quoted; if the re-run does not land on 39.410 and 39.395 the tails describe
#    some other run and the CSV says reproduced=NO rather than quietly carrying
#    them. That also re-checks determinism after the _logdir change.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
BIN=./htsim_tcp_glassfb_pm
mkdir -p "$PAPER" ./gt64tail_logs
CSV=$PAPER/cliff_ep64_tail.csv
csv_open "$CSV" "paper_ref,system,cabling,ep,nodes,mb,k,q,q_over_bdp,relayed_pairs,completed,makespan_ms,expected_ms,reproduced,rtos,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note"
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

run () { # k q expected_ms
  local k=$1 q=$2 exp=$3
  local log=./gt64tail_logs/${SLURM_JOB_ID:-local}_k${k}.log
  local ld t0 t1
  ld=$(_logdir)                      # ONCE: the run writes here and the tail is read here
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep64_gt.txt" \
    timeout 30000 $BIN -logdir "$ld" -nodes 512 -flowfile "$R/$QME" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep64.txt" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)

  local relay ps ms rtos comp st repro
  relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
  repro=$([ "$ms" = "$exp" ] && echo yes || echo NO)
  st=tail
  if [ "$rc" = "124" ]; then st=truncated
  elif [ "$ps" = "0" ]; then st=no_iteration
  elif [ "$relay" != "0" ]; then st=blocked
  elif [ "$repro" = "NO" ]; then st=did_not_reproduce; fi

  # payload FCT (>1 MSS), the convention used everywhere else: the zero-byte
  # all-to-all flows are floored to one packet and would otherwise crowd the tail
  # with records that moved nothing.
  local s
  s=$(awk '/^FCT/{n++; v=$5+0; if($4>1436){m++; p[m]=v; s+=v}}
       END{if(m==0){print "0,0,,,,"; exit} asort(p);
           printf "%d,%d,%.4f,%.4f,%.4f,%.4f", n, m, s/m, p[int(m*0.5)+1], p[int(m*0.99)+1], p[m]}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo "0,0,,,,")

  csv_row "$CSV" paper_ref=cliff system=glassfb cabling=ep64_gt ep=64 nodes=512 mb=8 \
    k="$k" q="$q" q_over_bdp="$k.0" relayed_pairs="$relay" completed="$comp" \
    makespan_ms="$ms" expected_ms="$exp" reproduced="$repro" rtos="$rtos" \
    flows_total="$(echo "$s" | cut -d, -f1)" flows_payload="$(echo "$s" | cut -d, -f2)" \
    mean_fct_ms="$(echo "$s" | cut -d, -f3)" p50_fct_ms="$(echo "$s" | cut -d, -f4)" \
    p99_fct_ms="$(echo "$s" | cut -d, -f5)" max_fct_ms="$(echo "$s" | cut -d, -f6)" \
    wall_s="$((t1-t0))" status="$st" \
    note="FCT tail re-measured; the walk's cells shared one logdir so its tails were unattributable"

  printf "  k=%-3s q=%-6s %-10s %10s ms (expected %s, reproduced=%s) rtos=%-6s maxFCT=%-9s wall=%-5ss [%s]\n" \
    "$k" "$q" "$comp" "$ms" "$exp" "$repro" "$rtos" "$(echo "$s" | cut -d, -f6)" "$((t1-t0))" "$st"
}

echo "########## Glass EP=64 FCT tails at 32x and 64x ##########"
run 32  8533 39.410
run 64 17067 39.395
csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-190
