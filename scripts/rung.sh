#!/bin/bash
# ONE rung of ONE vanishing-timeout walk, as its own job.
#
# The walks are normally sequential and stop at the first zero-timeout rung. With
# a day to finish everything, wall time is the scarce resource and compute is not,
# so every rung of every walk runs simultaneously and the quoting happens
# afterwards over the collected rows. The rule is unchanged -- the quoted row is
# still the first rung with no timeouts -- only the order of discovery is.
#
# EACH JOB WRITES ITS OWN CSV. About 170 jobs appending to one file would
# interleave rows and race every rewriter; the .writing marker protects against a
# reader, not against 169 other writers. scripts/collect_rungs.py merges them.
#
# Usage:
#   rung.sh glass <ep> <nodes> <fbuf> <wm> <portmap> <q> <mb> <tag>
#     env knobs: RUNG_DIM_A2A (1), RUNG_NO_PORTMAP, RUNG_HIER, RUNG_PORT_BW (400 GB/s)
#   rung.sh pkt   <sys> <ep> <nodes> <fbuf> <wm> <D> <S> <L> <nic> <q> <qc> <tag>
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
source /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/paper_csv.sh
_logdir() { printf './logs/rung_%s_%s_%s' "${SLURM_JOB_ID:-local}" "$$" "$(date +%s%N)"; }
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps
OUTD=../../../experiments/results/paper/rungs
mkdir -p "$OUTD" ./rung_logs

MODE=$1; shift

IS_GLASS=0; [ "$MODE" = glass ] || [ "$MODE" = glassdrop ] && IS_GLASS=1
if [ "$IS_GLASS" = 1 ]; then
  EP=$1 NODES=$2 FB=$3 WM=$4 MAP=$5 Q=$6 MB=$7 TAG=$8
  # glassdrop runs the drop-instrumented build so the row carries a measured
  # loss count; glass runs the plain one. Same cell either way.
  if [ "$MODE" = glassdrop ]; then BIN=./htsim_tcp_glassfb_drop; else BIN=./htsim_tcp_glassfb_pm; fi
  [ -x "$BIN" ] || { echo "FATAL: $BIN missing" >&2; exit 1; }
  CSV=$OUTD/${TAG}.csv
  csv_open "$CSV" "paper_ref,system,cabling,ep,nodes,mb,q,relayed_pairs,completed,makespan_ms,rtos,drops,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,max_fct_ms,fct_logdir,fct_status,wall_s,status,note"
  LD=$(_logdir); LOG=./rung_logs/${TAG}_${SLURM_JOB_ID:-local}.log
  T0=$(date +%s)
  # Optional knobs for the 2x2 (cabling x dim-route) and hierarchical cells.
  DIM=${RUNG_DIM_A2A:-1}
  HIER=""; [ "${RUNG_HIER:-0}" = 1 ] && HIER="-a2a_hier"
  # Inter-panel port rate in GB/s. The topology's default is 400; 800 is the
  # 200G/lane option. Passed explicitly rather than inherited, so a row can say
  # which rate it ran at instead of the reader having to know what was in the
  # environment when it was submitted.
  PORT_BW=${RUNG_PORT_BW:-400}
  # EP-aware placement. 0 is naive rank order, the ablation arm.
  PLACE=${RUNG_EP_PLACE:-1}
  echo "rung knobs: dim_a2a=$DIM portmap=${RUNG_NO_PORTMAP:+OMITTED}${RUNG_NO_PORTMAP:-$MAP} hier=${RUNG_HIER:-0} port_bw=$PORT_BW ep_place=$PLACE" >&2
  if [ "${RUNG_NO_PORTMAP:-0}" = 1 ]; then
    # mesh cabling: no port map at all, which is a different fabric, not a
    # different setting of one
    GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
    GLASS_EP_PLACE="$PLACE" GLASS_DIM_A2A="$DIM" GLASS_PORT_BW="$PORT_BW" \
      timeout 43200 $BIN -logdir "$LD" -nodes "$NODES" -flowfile "$R/$FB" \
        -disable-intra-shortcut -mtu 1500 -q "$Q" $HIER -weightmatrix "$T/$WM" > "$LOG" 2>&1
  else
    GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
    GLASS_EP_PLACE="$PLACE" GLASS_DIM_A2A="$DIM" GLASS_PORT_BW="$PORT_BW" GLASS_PORT_MAP="$PM/$MAP" \
      timeout 43200 $BIN -logdir "$LD" -nodes "$NODES" -flowfile "$R/$FB" \
        -disable-intra-shortcut -mtu 1500 -q "$Q" $HIER -weightmatrix "$T/$WM" > "$LOG" 2>&1
  fi
  RC=$?; T1=$(date +%s)
  RELAY=$(grep -oE "unmapped panel pair \([0-9]+,[0-9]+\)" "$LOG" | sort -u | wc -l)
  # A non-default port rate is a different fabric row, not a different setting of
  # one: RUNG_SYS names it so the 800 GB/s walk cannot land inside the 400 GB/s
  # design point's line in R1 or its rows in the power tables.
  SYS=${RUNG_SYS:-glassfb}; CAB=$MAP
else
  SYS=$1 EP=$2 NODES=$3 FB=$4 WM=$5 D=$6 SW=$7 L=$8 NIC=$9 Q=${10} QC=${11} TAG=${12}
  case "$SYS" in hgx8_pkt) BIN=./htsim_tcp_nvswitch_drop ;; *) BIN=./htsim_tcp_nvswitch ;; esac
  CSV=$OUTD/${TAG}.csv
  csv_open "$CSV" "paper_ref,system,ep,nodes,domain,switches,link_gbps,nic_bw,q_nvs,q_nic,makespan_ms,rtos,drops,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,max_fct_ms,fct_logdir,fct_status,wall_s,status,note"
  LD=$(_logdir); LOG=./rung_logs/${TAG}_${SLURM_JOB_ID:-local}.log
  T0=$(date +%s)
  GLASS_RTO_MIN_US=100 timeout 43200 $BIN -logdir "$LD" -nodes "$NODES" -flowfile "$R/$FB" \
      -nvs_domain "$D" -nvs_switches "$SW" -nvs_link "$L" -nvs_lat 250 \
      -nvs_q "$Q" -nvs_ecn_k $((Q / 2)) \
      -speed $((NIC * 8000)) -rtt 2000 -q "$QC" -port-cap-pkts $((QC / 2)) -mtu 1500 \
      -weightmatrix "$T/$WM" > "$LOG" 2>&1
  RC=$?; T1=$(date +%s)
  RELAY=0
fi

PS=$(grep "finished one iter" "$LOG" | tail -1 | grep -oE "now [0-9]+" | awk '{print $2}')
[ -z "$PS" ] && PS=0
MS=$(awk -v p="$PS" 'BEGIN{printf "%.3f", p/1e9}')
RTOS=$(grep -c '^At ' "$LOG")
DROPS=$(grep -m1 -oE "dropcount: [0-9]+" "$LOG" | awk '{print $2}')
ST=sweep
if [ "$RC" = "124" ]; then ST=truncated
elif [ "$PS" = "0" ]; then ST=no_iteration
elif [ "$RELAY" != "0" ]; then ST=blocked; fi

# payload FCT, read from this cell's own directory immediately after this cell
FSTAT=$(awk '/^FCT/{n++; v=$5+0; if($4>1436){m++; p[m]=v; s+=v}}
     END{if(m==0){print "0,0,,,,"; exit} asort(p);
         printf "%d,%d,%.4f,%.4f,%.4f,%.4f", n, m, s/m, p[int(m*0.5)+1], p[int(m*0.99)+1], p[m]}' \
    "$LD/fct_util_out.txt" 2>/dev/null || echo "0,0,,,,")

# The directory this cell's tail came from, recorded on the row. Without it a
# downstream reader has only the makespan to key on, and two cells that produce
# the same makespan -- a re-run reproducing the row it re-ran, for one -- become
# indistinguishable. FSTAT was read from $LD above, so this is where it came from,
# not a claim about where it should have come from.
# A 200G/lane row carries its own caveat. The link term is unaffected -- 1.15 pJ/bit
# is a DYNAMIC energy-per-bit figure (docs/energy_model.md), so doubling the lane
# rate moves the same bits faster and changes no joules per bit -- but the static
# laser+tuning term, 5.3 W per panel, was budgeted for 100G/lane and has not been
# re-derived. It is very likely low here, which flatters this fabric, so the row
# says so rather than a caption remembering to.
PBNOTE=""
[ "${RUNG_PORT_BW:-400}" != "400" ] && PBNOTE="; 200G/lane: static laser+tune NOT re-budgeted, same 5.3 W/panel as 100G/lane and likely low for the higher-rate lanes; link pJ/bit unchanged (dynamic)"
FLD="$LD"
FSTATUS=no_fct
[ "$(echo "$FSTAT"|cut -d, -f2)" -gt 0 ] 2>/dev/null && FSTATUS=clean

if [ "$IS_GLASS" = 1 ]; then
  csv_row "$CSV" paper_ref=cliff system=glassfb cabling="$CAB" ep="$EP" nodes="$NODES" \
    mb="$MB" q="$Q" relayed_pairs="$RELAY" completed="$([ "$RC" = 124 ] && echo TRUNCATED || echo COMPLETE)" \
    makespan_ms="$MS" rtos="$RTOS" drops="${DROPS:-}" \
    flows_total="$(echo "$FSTAT"|cut -d, -f1)" flows_payload="$(echo "$FSTAT"|cut -d, -f2)" \
    mean_fct_ms="$(echo "$FSTAT"|cut -d, -f3)" p50_fct_ms="$(echo "$FSTAT"|cut -d, -f4)" \
    p99_fct_ms="$(echo "$FSTAT"|cut -d, -f5)" max_fct_ms="$(echo "$FSTAT"|cut -d, -f6)" \
    fct_logdir="$FLD" fct_status="$FSTATUS" \
    wall_s="$((T1-T0))" status="$ST" note="post-fix rung ($MODE); dim_a2a=${RUNG_DIM_A2A:-1}; portmap=${RUNG_NO_PORTMAP:+none}${RUNG_NO_PORTMAP:-$MAP}; hier=${RUNG_HIER:-0}; port_bw=${RUNG_PORT_BW:-400}; ep_place=${RUNG_EP_PLACE:-1}${PBNOTE}"
else
  csv_row "$CSV" paper_ref=cliff system="$SYS" ep="$EP" nodes="$NODES" domain="$D" \
    switches="$SW" link_gbps="$L" nic_bw="$NIC" q_nvs="$Q" q_nic="$QC" \
    makespan_ms="$MS" rtos="$RTOS" drops="${DROPS:-}" \
    flows_total="$(echo "$FSTAT"|cut -d, -f1)" flows_payload="$(echo "$FSTAT"|cut -d, -f2)" \
    mean_fct_ms="$(echo "$FSTAT"|cut -d, -f3)" p50_fct_ms="$(echo "$FSTAT"|cut -d, -f4)" \
    p99_fct_ms="$(echo "$FSTAT"|cut -d, -f5)" max_fct_ms="$(echo "$FSTAT"|cut -d, -f6)" \
    fct_logdir="$FLD" fct_status="$FSTATUS" \
    wall_s="$((T1-T0))" status="$ST" note="post-fix rung; one job per rung"
fi
csv_close
printf "%s q=%-7s %10s ms rtos=%-8s drops=%-9s wall=%ss [%s]\n" \
  "$TAG" "$Q" "$MS" "$RTOS" "${DROPS:-}" "$((T1-T0))" "$ST"
