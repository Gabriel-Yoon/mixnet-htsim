#!/bin/bash
# paper_ref=mb: is the iteration time insensitive to microbatch?
#
# LLaMA-MoE EP=16 at mb 4/8/16/32, glass against packet-level NVL-64, 128 nodes.
#
# The quoted cell for each (system, mb) is the SHALLOWEST buffer at which that
# system's timeouts vanish -- the same rule used everywhere else -- and every
# attempt is recorded, not just the quoted one. So each cell walks q upward and
# stops at the first zero-RTO point; if none is reached, the best makespan is
# quoted and the row says so.
#
# BDP per tier, each link_bw x that link's own round trip:
#   glass inter-panel port  400 GB/s x 2 x 500 ns = 400 000 B = 267 pkt
#       -> q 1064 / 2133 / 4267 = 4x / 8x / 16x
#   NVLink port              50 GB/s x 4 x 250 ns =  50 000 B =  33 pkt
#       -> q 136 / 272 / 544 / 1088 = 4x / 8x / 16x / 32x
#
# EP=16 keeps the whole expert group inside one panel, so the all-to-all is
# intra-panel; what varies with mb is the DP and PP traffic and the pipeline
# fill. That is the claim being tested.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
# Unique output directory per invocation; the binary's default is a one-second
# timestamp that concurrent cells can share.
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }

R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./mb_logs
CSV=$PAPER/mb_sweep.csv
csv_open "$CSV" "paper_ref,model,model_name,workload_type,system,ep,mb,nodes,q,q_over_bdp,rto_min_us,mtu,relayed_pairs,completed,makespan_ms,rtos,wall_s,quoted,status,note"

glass_cell () { # mb q
  local mb=$1 q=$2
  local log=./mb_logs/glass_mb${mb}_q${q}_${SLURM_JOB_ID:-local}.log t0 t1
  local fb=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/ep16_0_8_4.txt" \
    timeout 20000 ./htsim_tcp_glassfb_pm -logdir "$(_logdir)" -nodes 128 -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  echo "$?:$(($(date +%s)-t0)):$log"
}

pkt_cell () { # mb q
  local mb=$1 q=$2
  local log=./mb_logs/nvl64_mb${mb}_q${q}_${SLURM_JOB_ID:-local}.log t0
  local fb=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb${mb}_H100.fbuf
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 \
    timeout 20000 ./htsim_tcp_nvswitch -logdir "$(_logdir)" -nodes 128 -flowfile "$R/$fb" \
      -nvs_domain 64 -nvs_switches 18 -nvs_link 50 -nvs_lat 250 \
      -nvs_q "$q" -nvs_ecn_k $((q / 2)) \
      -speed 800000 -rtt 2000 -q 540 -port-cap-pkts 270 -mtu 1500 \
      -weightmatrix "$T/wm_ep16.txt" > "$log" 2>&1
  echo "$?:$(($(date +%s)-t0)):$log"
}

# Walk q upward, stop at the first zero-RTO point, record every attempt.
sweep () { # system mb bdp_pkts q...
  local sys=$1 mb=$2 bdp=$3; shift 3
  local q rc wall log relay ps ms rtos comp st quoted found=0
  for q in "$@"; do
    if [ "$sys" = glassfb ]; then IFS=: read -r rc wall log <<<"$(glass_cell "$mb" "$q")"
    else                          IFS=: read -r rc wall log <<<"$(pkt_cell   "$mb" "$q")"; fi
    relay=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$log" | sort -u | wc -l)
    ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
    [ -z "$ps" ] && ps=0
    ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
    rtos=$(grep -c '^At ' "$log")
    [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE
    st=sweep
    if   [ "$rc" = "124" ]; then st=truncated
    elif [ "$ps" = "0" ];  then st=no_iteration
    elif [ "$relay" != "0" ]; then st=blocked; fi
    quoted=no
    if [ "$st" = sweep ] && [ "$rtos" = "0" ] && [ "$found" = 0 ]; then quoted=yes; found=1; fi
    csv_row "$CSV" paper_ref=mb model=pkt model_name=llamaMoE workload_type=training \
      system="$sys" ep=16 mb="$mb" nodes=128 q="$q" \
      q_over_bdp="$(awk -v q="$q" -v b="$bdp" 'BEGIN{printf "%.1f", q/b}')" \
      rto_min_us=100 mtu=1500 relayed_pairs="$relay" completed="$comp" \
      makespan_ms="$ms" rtos="$rtos" wall_s="$wall" quoted="$quoted" status="$st" \
      note="vanishing-timeout rule; quoted=yes is the shallowest zero-RTO buffer"
    printf "  %-9s mb=%-3s q=%-5s (%sx) -> %10s ms rtos=%-8s wall=%-5ss quoted=%s [%s]\n" \
      "$sys" "$mb" "$q" "$(awk -v q="$q" -v b="$bdp" 'BEGIN{printf "%.1f", q/b}')" \
      "$ms" "$rtos" "$wall" "$quoted" "$st"
    [ "$found" = 1 ] && break
  done
  [ "$found" = 0 ] && echo "      NOTE: no zero-RTO point in the sweep for $sys mb=$mb; quote the best makespan and say so"
}

for mb in 4 8 16 32; do
  echo "########## mb=$mb ##########"
  sweep glassfb   "$mb" 267 1064 2133 4267
  sweep nvl64_pkt "$mb"  33  136  272  544 1088
done
csv_close
echo "=== DONE ==="; column -s, -t "$CSV"
