#!/bin/bash
#SBATCH -J qwenmoe_L4_delay
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=24G
#SBATCH -t5:00:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_qwenmoe_L4_delay.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter/_sbatch_qwenmoe_L4_delay.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/src/clos/datacenter
FB=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-flexflow/results/qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq4096_mb8_H100.fbuf
WM64=/storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/mixnet-htsim/test/wm_ep64.txt
mkdir -p logs/wafer_delay_sweep
t0=$(date +%s)
timeout 16800 ./htsim_tcp_wafer -nodes 512 -wafer-rows 4 -wafer-cols 4 -intra-delay 78 -thermal-delay 46760000 -flowfile "$FB" -weightmatrix "$WM64" -q 10000 > logs/wafer_delay_sweep/qwenmoe_L4_delay.log 2>&1
rc=$?
t1=$(date +%s)
ok=$(grep -ac 'finished one iter' logs/wafer_delay_sweep/qwenmoe_L4_delay.log)
ps=$(grep -aoE 'now [0-9]+' logs/wafer_delay_sweep/qwenmoe_L4_delay.log | tail -1 | awk '{print $2}')
[ -z "$ps" ] && ps=0
[ "$ok" -eq 0 ] && ps=0
ms=$(awk -v p="$ps" 'BEGIN{printf "%.4f", p/1e9}')
echo "qwen-moe-14.3b,4,512,46760000,physical_derived,$ps,$ms,$((t1-t0)),rc=$rc" > qwenmoe_L4_delay_result.csv
echo "RESULT: L4_delay -> ${ms}ms (wall $((t1-t0))s, ok=$ok, rc=$rc)"
echo QWENMOE_L4_delay_DONE
