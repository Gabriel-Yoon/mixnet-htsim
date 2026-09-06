#!/bin/bash
# SCALE sweep: glass-FB (design) vs REALIZABLE electrical fat-tree across GPU scale (128 -> 1280+).
# RUN ON AN HPC COMPUTE NODE (CPU only; mixnet-htsim is CPU-only).
# Compares glass (elec1800/opt400/inter200, panel16, EP-placed) against fat-tree @50/100 GB/s (the
# MixNet electrical range) and flat (full-bisection upper bound), on each profiled proxy at its native
# scale. gb200/h100 were DROPPED: their NVLink-domain + IB model is placement-sensitive (how dp/pp/ep
# map to domains) and unfair without per-fabric optimal placement — that is a separate modeling task.
# Verbose stdout is filtered to the makespan line only.
#
# Prereq: build htsim on this node first ->  bash mixnet-htsim/mixnet_scripts/compile.sh
#
#   bash scripts/htsim_nvl72_crossover.sh                 # all proxies, all fabrics
#   JOBS=8 bash scripts/htsim_nvl72_crossover.sh          # cap concurrency (default = nproc/4)
set -uo pipefail
ROOT=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim
BIN=$ROOT/mixnet-htsim/src/clos/datacenter
R=$ROOT/mixnet-flexflow/results
OUT=$ROOT/outputs/nvl72_crossover; mkdir -p "$OUT"
# per-run CSV (set TAG so a small login-node run and a big compute-node run don't clobber; plot globs all)
CSV=$OUT/nvl72_crossover${TAG:+_$TAG}.csv
echo "model,nodes,fabric,intra_bw,inter_bw,panel,makespan_ps,makespan_ms" > "$CSV"
JOBS="${JOBS:-$(( $(nproc 2>/dev/null || echo 8) / 4 ))}"; [ "$JOBS" -lt 1 ] && JOBS=1
cd "$BIN"

# nodes = dp*tp*pp*ep, parsed from the filename (..._dp2tp1pp4_ep128...)
nodes_of(){ local f=$(basename "$1"); local dp tp pp ep
  dp=$(echo "$f"|grep -oE 'dp[0-9]+'|grep -oE '[0-9]+'); tp=$(echo "$f"|grep -oE 'tp[0-9]+'|grep -oE '[0-9]+')
  pp=$(echo "$f"|grep -oE 'pp[0-9]+'|grep -oE '[0-9]+'); ep=$(echo "$f"|grep -oE 'ep[0-9]+'|grep -oE '[0-9]+')
  [ -n "$dp" ] && [ -n "$tp" ] && [ -n "$pp" ] && [ -n "$ep" ] && echo $((dp*tp*pp*ep)) || echo 0; }
mk(){ grep -aE 'finished one iter' "$1" 2>/dev/null | grep -aoE 'now [0-9]+'|tail -1|awk '{print $2}'; }

# fabric -> "panel intra inter binary glassenv"  (glass via glassfb binary; fat-tree/flat separate)
run_one(){  # model nodes fabric panel intra inter fbuf tp ep wm
  local m=$1 nd=$2 fab=$3 panel=$4 intra=$5 inter=$6 fb=$7 tp=$8 ep=$9 wm=${10}
  local log=$OUT/${m}_${nd}_${fab}.log
  # EP placement co-locates each EP group in its scale-up domain (panel). -q 10000 and -weightmatrix
  # match the mixnet_baselines sweep exactly (q=1e6 caused bufferbloat + unusably slow sims).
  local place="GLASS_EP_PLACE=1 GLASS_TP=$tp GLASS_EP=$ep"
  case "$fab" in
    fattree50|fattree100)
      local sp=$([ "$fab" = fattree50 ] && echo 400000 || echo 800000)
      ./htsim_tcp_fattree -nodes $nd -flowfile "$fb" -speed $sp -q 10000 -weightmatrix "$wm" 2>&1 \
        | grep -aE 'finished one iter' > "$log" ;;
    flat100)  # full-bisection (idealized upper bound) at 100 GB/s
      ./htsim_tcp_flat -nodes $nd -flowfile "$fb" -speed 800000 -q 10000 -weightmatrix "$wm" 2>&1 \
        | grep -aE 'finished one iter' > "$log" ;;
    glass)
      # our REAL design: distance-layered elec 1800 (adjacent RDL) / opt $intra (far) / inter $inter,
      # inter-panel = OCS FullyConnected (1 hop) at any P per the documented design.
      env $place GLASS_PANEL=$panel GLASS_FORCE_DFLY=1 GLASS_ELEC_BW=1800 GLASS_OPT_BW=$intra GLASS_INTER_BW=$inter \
        ./htsim_tcp_glassfb -nodes $nd -flowfile "$fb" -q 10000 -weightmatrix "$wm" 2>&1 \
        | grep -aE 'finished one iter' > "$log" ;;
    *)  # gb200 / h100 modeled via the 2-tier glassfb: panel = NVLink domain, uniform intra, IB inter
      env $place GLASS_PANEL=$panel GLASS_INTRA_BW=$intra GLASS_INTER_BW=$inter \
        ./htsim_tcp_glassfb -nodes $nd -flowfile "$fb" -q 10000 -weightmatrix "$wm" 2>&1 \
        | grep -aE 'finished one iter' > "$log" ;;
  esac
  local ps=$(grep -aoE 'now [0-9]+' "$log"|tail -1|awk '{print $2}'); [ -z "$ps" ]&&ps=0
  echo "$m,$nd,$fab,$intra,$inter,$panel,$ps,$(awk -v p=$ps 'BEGIN{printf "%.3f",p/1e9}')" >> "$CSV"
}

# proxy fbufs to sweep. GLOB env overrides (default L4 only — light enough for a login node;
# add L8/L16 on a real compute node). e.g. GLOB="*_L4_seq1024_*.fbuf *_L8_seq4096_*.fbuf"
running=0
for fb in $(for g in ${GLOB:-"*_L4_seq1024_*.fbuf"}; do echo $R/$g; done); do
  [ -f "$fb" ] || continue
  nd=$(nodes_of "$fb"); [ "$nd" -lt 16 ] && continue
  bn=$(basename "$fb"); tp=$(echo "$bn"|grep -oE 'tp[0-9]+'|grep -oE '[0-9]+'); ep=$(echo "$bn"|grep -oE 'ep[0-9]+'|grep -oE '[0-9]+')
  m=$(basename "$fb"|sed -E 's/_(paper|tpsweep).*//')
  # same skewed a2a weightmatrix as the baselines sweep (auto-generate ep x ep on first use)
  wm=$ROOT/mixnet-htsim/test/num_global_tokens_per_expert.txt
  if [ "$ep" != 8 ]; then
    wm=$ROOT/mixnet-htsim/test/wm_ep${ep}.txt
    [ -s "$wm" ] || python3 "$ROOT/scripts/gen_weightmatrix.py" "$ep" > "$wm" 2>/dev/null
    [ -s "$wm" ] || { echo "  [wm] cannot generate ep=$ep -- skipping $m"; continue; }
  fi
  echo "### $m  nodes=$nd tp=$tp ep=$ep"
  # glass = design (elec1800/opt400/inter200) vs REALIZABLE electrical fat-tree @50/100 GB/s
  # (MixNet range) + flat (full-bisection upper bound). gb200/h100 dropped: their NVLink-domain+IB
  # model is placement-sensitive (dp/pp/ep mapping) and not fair without per-fabric optimal placement.
  for spec in "glass 16 400 200" "fattree50 0 50 0" "fattree100 0 100 0" "flat100 0 100 0"; do
    read -r fab panel intra inter <<< "$spec"
    # skip glass (panel-based) if panel does not divide nodes (avoids single-panel fallback)
    [ "$fab" = glass ] && [ $((nd % panel)) -ne 0 ] && continue
    run_one "$m" "$nd" "$fab" "$panel" "$intra" "$inter" "$fb" "$tp" "$ep" "$wm" &
    running=$((running+1)); [ "$running" -ge "$JOBS" ] && { wait -n 2>/dev/null || wait; running=$((running-1)); }
  done
done
wait
echo "DONE -> $CSV"; column -t -s, "$CSV" | sort -k2 -n
