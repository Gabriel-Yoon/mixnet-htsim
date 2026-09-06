#!/bin/bash
# MixNet-paper-style topology comparison: glass-FB vs the MixNet (SIGCOMM'25) baselines, on the
# same SKEWED a2a (every topology gets -weightmatrix), swept over the paper's link-BW range and
# over MICROBATCH (a2a load axis). y-axis = iteration time (makespan).
#
# CROSSOVER: glass-FB beats fat-tree at small microbatch (light a2a) and loses at large microbatch
# (heavy a2a saturates the 4x4 panel's limited bisection). The microbatch column makes this plottable.
#
# IMPORTANT FINDINGS that shaped this script:
#  - MixNet (`htsim_tcp_mixnet`) only runs for EP=8 (bundled weightmatrix is 8x8, indexed %8; ep!=8
#    hits `when>=now()`). os_fattree can crash (-> 0). Those rows just record 0 and are skipped in plots.
#  - All topologies use -weightmatrix so the a2a skew is identical (fair to MixNet's reconfiguration).
#  - glass_fb uses the DESIGN BW (elec 1800 / opt 400 / inter 200 GB/s) + EP-panel placement; it is
#    BW-independent (recorded at link_gbps=4096, drawn as a reference line / point in plots).
#
# PARALLEL USE (multi-node): set TAG per node so each writes its OWN CSV (no clobber); merge later.
#   e.g. node A:  TAG=mixtral8x7B ... bash htsim_mixnet_baselines.sh mixtral8x7B
#        node B:  TAG=llamaMoE    ... bash htsim_mixnet_baselines.sh llamaMoE
# Optional MBS env filters microbatches (e.g. MBS="4 8") so a slow large-mb run can go on its own node.
set -uo pipefail
ROOT="${ROOT:-/Users/seongwonyoon/Documents/vscode_workspace/github-repos/mixnet-sim}"
BIN=$ROOT/mixnet-htsim/src/clos/datacenter
WM=$ROOT/mixnet-htsim/test/num_global_tokens_per_expert.txt
TG="${TG:-$ROOT/taskgraph}"
OUT="${OUT:-/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots}"
mkdir -p "$OUT"; cd "$BIN"
# per-invocation CSV so parallel jobs on different nodes don't clobber a shared file
TAG="${TAG:-$(echo ${*:-all} | tr ' ' '-')}"
CSV=$OUT/mixnet_baselines_${TAG}.csv
echo "model,nodes,ep,microbatch,topology,link_gbps,makespan_ps,makespan_ms" > "$CSV"
read -r -a BWS <<< "${BWS:-100 200 400 600 800}"     # Gbps (MixNet paper range)
read -r -a MBS <<< "${MBS:-}"                          # optional microbatch filter, e.g. "4 8 16 32"

deg(){ basename "$1"|grep -oE "${2}[0-9]+"|grep -oE '[0-9]+'|head -1; }
in_list(){ local x=$1; shift; [ $# -eq 0 ] && return 0; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }
frun(){ "$@" 2>&1 | grep -aE 'finished one iter' | grep -aoE 'now [0-9]+'|tail -1|awk '{print $2}'; }
# emit: ps model nodes ep mb topology bw
emit(){ local ps=$1;[ -z "$ps" ]&&ps=0;echo "$2,$3,$4,$5,$6,$7,$ps,$(awk -v p=$ps 'BEGIN{printf "%.3f",p/1e9}')">>"$CSV";echo "  [$2 mb$5 $6 @${7}Gb] $(awk -v p=$ps 'BEGIN{printf "%.1f",p/1e9}')ms"; }

# model discovery: when model prefixes are passed as args, glob exactly those (works for ANY model,
# e.g. arctic, dbrx, mixtral8x22B, mixtral8x7B_tpsweep). Otherwise the default paper set.
MF="$*"
if [ -n "$MF" ]; then PATS=""; for mm in $MF; do PATS="$PATS $TG/${mm}_*_L4_seq1024_*.fbuf"; done
else PATS="$TG/grok1_*_L4_seq1024_*.fbuf $TG/mixtral8x7B_paper_*_L4_seq1024_*.fbuf $TG/llamaMoE_paper_*_L4_seq1024_*.fbuf $TG/qwenMoE_paper_*_L4_seq1024_*.fbuf"; fi
for fb in $PATS; do
  [ -f "$fb" ] || continue
  m=$(basename "$fb"|sed -E 's/_(paper|dp).*//')
  dp=$(deg "$fb" dp); tp=$(deg "$fb" tp); pp=$(deg "$fb" pp); ep=$(deg "$fb" ep); mb=$(deg "$fb" mb)
  in_list "$mb" "${MBS[@]}" || continue
  nd=$((dp*tp*pp*ep)); wm="$WM"
  if [ "$ep" != 8 ]; then
    wm="$ROOT/mixnet-htsim/test/wm_ep${ep}.txt"
    # auto-generate the ep x ep weightmatrix on first use (any EP), so new models just work
    [ -s "$wm" ] || { echo "  [wm] generating ep=$ep weightmatrix -> $wm"; python3 "$ROOT/scripts/gen_weightmatrix.py" "$ep" > "$wm" 2>/dev/null || true; }
    [ -s "$wm" ] || { echo "  [wm] FAILED to generate ep=$ep weightmatrix -- skipping $m"; continue; }
  fi
  echo "### $m nodes=$nd ep=$ep mb=$mb"
  for b in "${BWS[@]}"; do
    sp=$((b*1000)); ld=./logs/mb_${m}_${mb}_${b}; mkdir -p "$ld"
    emit "$(frun ./htsim_tcp_fattree -nodes $nd -flowfile "$fb" -speed $sp -q 10000 -weightmatrix "$wm")" "$m" $nd $ep $mb fattree $b
    osk=8; osnlp=$((nd/32)); [ $osnlp -lt 4 ] && { osk=4; osnlp=$((nd/8)); }
    emit "$(frun ./htsim_tcp_os_fattree -k $osk -nlp $osnlp -flowfile "$fb" -speed $sp -q 10000 -weightmatrix "$wm")" "$m" $nd $ep $mb os_fattree $b
    emit "$(frun ./htsim_tcp_flat    -nodes $nd -flowfile "$fb" -speed $sp -q 10000 -weightmatrix "$wm")" "$m" $nd $ep $mb flat $b
    emit "$(frun ./htsim_tcp_mixnet -simtime 3600.1 -flowfile "$fb" -speed $sp -nodes $nd -dp_degree $dp -tp_degree $tp -pp_degree $pp -ep_degree $ep -rdelay 25 -weightmatrix "$wm" -q 10000 -rtt 1000 -ssthresh 10000 -logdir "$ld")" "$m" $nd $ep $mb mixnet $b
  done
  # glass-FB design BW (elec 1800/opt 400/inter 200) + EP-panel placement; BW-independent (link_gbps=4096)
  emit "$(GLASS_PANEL=16 GLASS_EP_PLACE=1 GLASS_TP=$tp GLASS_EP=$ep frun ./htsim_tcp_glassfb -nodes $nd -flowfile "$fb" -q 10000 -weightmatrix "$wm")" "$m" $nd $ep $mb glass_fb 4096
done
echo "DONE -> $CSV"
command -v column >/dev/null 2>&1 && column -t -s, "$CSV" || cat "$CSV"
