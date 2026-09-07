#!/bin/bash
# All-pairs (mode 0) inter-panel cabling, with every MTP-16 port lit.
#
# WHY. The mesh (mode 2) has no wrap-around, so at 2 panels there is ONE edge
# between them: 1600 GB/s shared by 16 GPUs = 100 GB/s per GPU, the same as an
# 800G NIC, while the panel physically has 16 MTP-16 ports (400 GB/s each at
# 100G/lane = 6400 GB/s of egress). Three quarters of the panel's optical egress
# was stranded by the cabling choice, not by the optics. At 4 panels (2x2 mesh)
# two of four edges are used and the diagonal pair relays.
#
# For P <= 17 panels the ports can instead be cabled all-pairs: every panel pair
# direct, one hop, no relay. Ports lit = (P-1) * G, which must be <= 16.
#   EP=32,  P=2, deg=1 -> G=16, 6400 GB/s per pair  (16 ports lit)
#   EP=64,  P=4, deg=3 -> G=5,  2000 GB/s per pair  (15 ports lit)
#   EP=128, P=8, deg=7 -> G=2,   800 GB/s per pair  (14 ports lit)
# The per-GPU waveguide budget is unchanged: one port = 12.5 WG, so a GPU sits at
# 24 + 12.5 = 36.5 WG, the same as the mesh corner tile.
#
# Transport is derived for the SUB-LINK rate (inter_bw/G), not the pair rate.
set -uo pipefail
# Unique output directory per invocation. The binary's default is a
# one-second timestamp, which two concurrent cells can share; see
# scripts/logdir_collisions.py and methods_provenance.md sub-class I.
_LOGDIR_N=0
_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); printf './logs/%s_%s_%s_%s' "$(basename "$0" .sh)" "${SLURM_JOB_ID:-local}" "$$" "$_LOGDIR_N"; }
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PAPER=../../../experiments/results/paper
mkdir -p "$PAPER" ./df16_logs
CSV=$PAPER/cliff_dragonfly16.csv
csv_open "$CSV" "paper_ref,model,cabling,workload_type,model_name,topk,ep,mb,nodes,panels,system,inter_mode,inter_bw_pair,G,sublink_gbs,ports_lit,per_gpu_xpanel_gbs,opt_bw,elec_bw,q,q_over_bdp,rto_min_us,mtu,makespan_ms,rtos,flows,mean_fct_ms,p99_fct_ms,max_fct_ms,wall_s,status,note"
run () { # tag model topk ep nodes fbuf wm panels interbw G q
  local tag=$1 mdl=$2 topk=$3 ep=$4 nodes=$5 fb=$6 wm=$7 P=$8 ibw=$9 G=${10} q=${11}
  # PANELS_DERIVED: the topology builds nodes/16 panels regardless of what the
  # caller passes. Passing the EP group span here made ports_lit and
  # per_gpu_xpanel_gbs wrong for every row.
  local P_arg=$P
  P=$((nodes / 16))
  local log=./df16_logs/${tag}_${SLURM_JOB_ID:-local}.log t0 t1 wall
  t0=$(date +%s)
  GLASS_RTO_MIN_US=100 GLASS_INTER=dragonfly GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=384 GLASS_INTER_BW=$ibw GLASS_GW_PARALLEL=$G \
    timeout 30000 ./htsim_tcp_glassfb -logdir "$(_logdir)" -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q "$q" -weightmatrix "$T/$wm" > "$log" 2>&1
  t1=$(date +%s); wall=$((t1-t0))
  local ps ms rtos flows ld f gact sub ports pergpu qob
  ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
  [ -z "$ps" ] && ps=0
  ms=$(awk -v p="$ps" 'BEGIN{printf "%.3f", p/1e9}')
  rtos=$(grep -c '^At ' "$log")
  flows=$(grep -c 'flow_size:' "$log")
  ld=$(grep -m1 "Log directory is" "$log" | awk '{print $4}')
  f=$(awk '/^FCT/{n++; v=$5+0; s+=v; a[n]=v; if(v>mx)mx=v}
           END{if(n==0){print ",,"; exit} asort(a); printf "%.4f,%.4f,%.4f", s/n, a[int(n*0.99)], mx}' \
      "$ld/fct_util_out.txt" 2>/dev/null || echo ",,")
  # did the topology clamp G?
  gact=$(grep -m1 "clamping to" "$log" | grep -oE "clamping to [0-9]+" | awk '{print $3}')
  [ -z "$gact" ] && gact=$G
  # The topology clamps GW_PARALLEL when the panel degree cannot carry it. A
  # clamped run is a different experiment from the one requested, so it is
  # recorded blocked rather than final.
  local st=final note="all-pairs cabling; ports lit"
  if [ "$gact" != "$G" ]; then
    st=blocked; note="GW_PARALLEL clamped $G->$gact by panel degree; not the requested cabling"
  fi
  if [ "$P_arg" != "$P" ]; then
    note="$note; caller passed panels=$P_arg, topology built $P"
  fi
  sub=$(awk -v i="$ibw" -v g="$gact" 'BEGIN{printf "%.1f", i/g}')
  ports=$(awk -v p="$P" -v g="$gact" 'BEGIN{printf "%d", (p-1)*g}')
  pergpu=$(awk -v po="$ports" 'BEGIN{printf "%.1f", po*400/16}')
  # canonical BDP = link_bw * 4 * one-way latency. The glass banner reports
  # lat 100/300/500 ns, so the inter-panel tier is 500 ns and 4*lat = 2 us.
  # This was 5e-7, i.e. ONE one-way latency, which reported q as 4x too many BDP.
  qob=$(awk -v q="$q" -v s="$sub" 'BEGIN{printf "%.1f", (q*1500)/(s*1e9*2e-6)}')
  echo "cliff,pkt_glass,dragonfly16,training,$mdl,$topk,$ep,8,$nodes,$P,glassfb,dragonfly,$ibw,$gact,$sub,$ports,$pergpu,384,1800,$q,$qob,100,1500,$ms,$rtos,$flows,$f,$wall,$st,$note $ports/16" >> "$CSV"
  printf "  %-22s P=%-2s G=%-3s sub=%-7s ports=%-3s/16  perGPU=%-6s -> %10s ms rtos=%-7s wall=%ss\n" \
    "$tag" "$P" "$gact" "$sub" "$ports" "$pergpu" "$ms" "$rtos" "$wall"
}

L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
Q57=qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

# q derived for the SUB-LINK: BDP = sub_GBps * 500 ns. 400 GB/s -> 200 KB -> 133 pkt.
# 8x BDP ~ 1064; 2000/5=400 same; 800/2=400 same. All sub-links are 400 GB/s by design.
echo "########## EP=32, 2 panels, all 16 ports lit (6400 GB/s per pair) ##########"
run df16_ep32      llamaMoE  2  32  256 "$L32" wm_ep32.txt 2 6400 16 1064
echo "########## EP=64, 4 panels, 15 ports lit (2000 GB/s per pair) ##########"
run df16_ep64_qme  qwenMoE   4  64  512 "$QME" wm_ep64.txt 4 2000  5 1064
run df16_ep64_q57  qwen2_57b 8  64  512 "$Q57" wm_ep64.txt 4 2000  5 1064
echo "########## EP=64, the simpler 12-port variant ##########"
run df12_ep64_qme  qwenMoE   4  64  512 "$QME" wm_ep64.txt 4 1600  4 1064
echo "########## EP=128, 8 panels, 14 ports lit (800 GB/s per pair) ##########"
run df16_ep128_arc arctic    2 128 1024 "$ARC" wm_ep128.txt 8 800  2 1064

csv_close
echo "=== DONE ==="; column -s, -t "$CSV" | cut -c1-200
