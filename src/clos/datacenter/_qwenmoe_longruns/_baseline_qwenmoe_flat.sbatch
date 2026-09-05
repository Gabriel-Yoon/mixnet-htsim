#!/bin/bash
#SBATCH -J qwenmoe_baseline_flat
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=24G
#SBATCH -t5:00:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_qwenmoe_baseline_flat.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_qwenmoe_baseline_flat.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter
FB=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq4096_mb8_H100.fbuf
WM64=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/wm_ep64.txt
t0=$(date +%s)
timeout 16800 ./htsim_tcp_flat -nodes 512 -flowfile "$FB" -speed 400000 -q 10000 -weightmatrix "$WM64" > logs/wafer_delay_sweep/qwenmoe_baseline_flat.log 2>&1
rc=$?
t1=$(date +%s)
ps=$(grep -aoE 'now [0-9]+' logs/wafer_delay_sweep/qwenmoe_baseline_flat.log | tail -1 | awk '{print $2}')
[ -z "$ps" ] && ps=0
ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
echo "qwen-moe-14.3b,512,64,flat,400,$ps,$ms,$((t1-t0))" > qwenmoe_baseline_flat_result.csv
echo "RESULT: flat -> ${ms}ms (wall $((t1-t0))s, rc=$rc)"
