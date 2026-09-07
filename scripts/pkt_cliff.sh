#!/bin/bash
# Packet-level NVLink baselines for the cliff, at the buffer the k sweep chose.
#
# BUFFER, stated absolutely to avoid the k ambiguity: the sweep's "k" was indexed
# on a 2*lat BDP (17 pkt), while the banner and CSV use the canonical 4*lat round
# trip (33 pkt at 50 GB/s). The chosen point is therefore q=544 packets, which is
# 16.3x the canonical BDP, not 32x. Quoting q absolutely removes the ambiguity.
# The same relative depth is given to the HGX tier: at 112.5 GB/s the canonical
# BDP is 75 pkt, so 16.3x is q=1224.
#
# Both systems carry a `model` column so the figure can draw the contention-free
# island as a dashed bound above the queued curve.
set -uo pipefail
# Unique output directory per invocation. The binary's default is a
# one-second timestamp, which two concurrent cells can share; see
# scripts/logdir_collisions.py and methods_provenance.md sub-class I.
# Unique per CALL: the old counter incremented inside $(_logdir)'s subshell and never
# reached the parent, so every cell of a job shared one directory.
_logdir() { printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./pktcliff_logs
CSV=$PAPER/cliff_pkt.csv
csv_warn_truncate "$CSV" "paper_ref,model,workload_type,ep_source,model_name,topk,ep,mb,nodes,system,domain,switches,link_gbps,nvs_lat_ns,nic_bw,rtt_ns,q_nvs,q_over_bdp_4lat,q_nic,rto_min_us,mtu,makespan_ms,rtos,flows,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note"
echo "paper_ref,model,workload_type,ep_source,model_name,topk,ep,mb,nodes,system,domain,switches,link_gbps,nvs_lat_ns,nic_bw,rtt_ns,q_nvs,q_over_bdp_4lat,q_nic,rto_min_us,mtu,makespan_ms,rtos,flows,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note" > "$CSV"

run () { # sys model topk ep nodes fbuf wm D S L nic q_nvs q_nic
  local sys=$1 mdl=$2 topk=$3 ep=$4 nodes=$5 fb=$6 wm=$7 D=$8 S=$9 L=${10} nic=${11} qn=${12} qc=${13}
  local tag=${sys}_ep${ep}
  # separate statement: bash expands every RHS before local binds any of them,
  # so a ${tag} reference on that same line is unbound under set -u
  local log=./pktcliff_logs/${tag}_${SLURM_JOB_ID:-local}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 30000 ./htsim_tcp_nvswitch -logdir "$(_logdir)" -nodes "$nodes" -flowfile "$R/$fb" \
    -nvs_domain "$D" -nvs_switches "$S" -nvs_link "$L" -nvs_lat 250 \
    -nvs_q "$qn" -nvs_ecn_k $((qn / 2)) \
    -speed $((nic * 8000)) -rtt 2000 -q "$qc" -port-cap-pkts $((qc / 2)) \
    -mtu 1500 -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos flows ld f qob
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  f=$(awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if(v>mx)mx=v}
           END{if(n==0){print ",,"; exit} asort(a); printf "%.4f,%.4f,%.4f", s/n, a[int(n*0.99)], mx}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo ",,")
  # canonical BDP = L * 4*lat
  qob=$(awk -v q="$qn" -v l="$L" 'BEGIN{printf "%.1f", (q*1500)/(l*1e9*1e-6)}')
  echo "cliff,pkt,training,flexflow_${mdl},$mdl,$topk,$ep,8,$nodes,$sys,$D,$S,$L,250,$nic,2000,$qn,$qob,$qc,100,1500,$ms,$rtos,$flows,$f,$wall,final,packet-level NVSwitch; stripe=ecmp (mode 1); island OFF" >> "$CSV"
  printf "  %-14s ep=%-4s D=%-3s S=%-3s L=%-6s q=%-5s (%sx BDP) -> %10s ms rtos=%-7s wall=%ss\n" \
    "$sys" "$ep" "$D" "$S" "$L" "$qn" "$qob" "$ms" "$rtos" "$wall"
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
Q64=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf

echo "########## NVL-64 packet-level (D=64, S=18, L=50) ##########"
run nvl64_pkt llamaMoE 2 32 256 "$L32" wm_ep32.txt 64 18 50 100 544 540
run nvl64_pkt qwenMoE  4 64 512 "$Q64" wm_ep64.txt 64 18 50 100 544 540
echo "########## HGX-8 packet-level (D=8, S=4, L=112.5) ##########"
run hgx8_pkt  llamaMoE 2 16 128 "$L16" wm_ep16.txt  8  4 112.5 50 1224 270
run hgx8_pkt  llamaMoE 2 32 256 "$L32" wm_ep32.txt  8  4 112.5 50 1224 270
run hgx8_pkt  qwenMoE  4 64 512 "$Q64" wm_ep64.txt  8  4 112.5 50 1224 270

echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-190
