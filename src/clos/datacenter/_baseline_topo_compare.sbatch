#!/bin/bash
#SBATCH -J baseline_topo_compare
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=16G
#SBATCH -t1:30:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_baseline_topo.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_baseline_topo.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter
FB_LLAMA=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq4096_mb8_H100.fbuf
FB_MIXTRAL=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/mixtral8x7B_paper_dp2tp4pp4_ep8top2_L4_seq4096_mb8_H100.fbuf
WM16=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/wm_ep16.txt
WM8=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/num_global_tokens_per_expert.txt
OUT=baseline_topo_compare_results.csv
echo 'model,nodes,ep,topology,link_gbps,makespan_ps,makespan_ms' > $OUT

frun(){ "$@" 2>&1 | grep -aE 'finished one iter' | grep -aoE 'now [0-9]+'|tail -1|awk '{print $2}'; }
emit(){ local ps=$1;[ -z "$ps" ]&&ps=0;echo "$2,$3,$4,$5,$6,$ps,$(awk -v p=$ps 'BEGIN{printf "%.3f",p/1e9}')">>"$OUT";echo "  [$2 $5 @${6}Gb] $(awk -v p=$ps 'BEGIN{printf "%.1f",p/1e9}')ms"; }

for bw in 400 800; do
  sp=$((bw*1000))
  emit "$(frun timeout 600 ./htsim_tcp_fattree -nodes 256 -flowfile "$FB_MIXTRAL" -speed $sp -q 10000 -weightmatrix "$WM8")" mixtral8x7b 256 8 fattree $bw
  emit "$(frun timeout 600 ./htsim_tcp_flat -nodes 256 -flowfile "$FB_MIXTRAL" -speed $sp -q 10000 -weightmatrix "$WM8")" mixtral8x7b 256 8 flat $bw
  emit "$(frun timeout 600 ./htsim_tcp_mixnet -simtime 3600.1 -flowfile "$FB_MIXTRAL" -speed $sp -nodes 256 -dp_degree 2 -tp_degree 4 -pp_degree 4 -ep_degree 8 -rdelay 25 -weightmatrix "$WM8" -q 10000 -rtt 1000 -ssthresh 10000)" mixtral8x7b 256 8 mixnet $bw

  emit "$(frun timeout 600 ./htsim_tcp_fattree -nodes 128 -flowfile "$FB_LLAMA" -speed $sp -q 10000 -weightmatrix "$WM16")" llama-moe-6.7b 128 16 fattree $bw
  emit "$(frun timeout 600 ./htsim_tcp_flat -nodes 128 -flowfile "$FB_LLAMA" -speed $sp -q 10000 -weightmatrix "$WM16")" llama-moe-6.7b 128 16 flat $bw
  emit "$(frun timeout 600 ./htsim_tcp_mixnet -simtime 3600.1 -flowfile "$FB_LLAMA" -speed $sp -nodes 128 -dp_degree 2 -tp_degree 1 -pp_degree 4 -ep_degree 16 -rdelay 25 -weightmatrix "$WM16" -q 10000 -rtt 1000 -ssthresh 10000)" llama-moe-6.7b 128 16 mixnet $bw
done
echo BASELINE_TOPO_DONE
