#!/bin/bash
#SBATCH --job-name=isopower-sweep
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_isopower_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_isopower_%j.err

set -uo pipefail

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp

REPO=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif

apptainer exec --cleanenv \
  --bind /storage/home/hcoda1/8/syoon351/scratch:/storage/home/hcoda1/8/syoon351/scratch \
  --bind /storage/scratch1/8/syoon351/repos:/storage/scratch1/8/syoon351/repos \
  --bind /storage/project/r-syu334-0:/storage/project/r-syu334-0 \
  --pwd "$REPO/src/clos/datacenter" \
  "$SIF" \
  bash -c '
    set -uo pipefail
    cd '"$REPO"'/src/clos/datacenter
    mkdir -p ../../../experiments/results ./isopower_logs
    CSV=../../../experiments/results/serving_sweep_isopower.csv
    echo "workload,ep,nodes,topology,bw_gbps,G,fair_speed_mbps,glassfb_agg_gbps,glassfb_power_w,makespan_ps,makespan_ms,rtos" > "$CSV"

    # Iso-power methodology (per manuscript-revision session, matches main.tex
    # Table~tab:power / Fig. isopower): interconnect power per GPU = aggregate
    # simultaneous per-GPU bandwidth (bits/s) x link-technology pJ/bit.
    # Glass-FB per-GPU aggregate = elec(1800GB/s, fixed) + opt(400GB/s, fixed)
    #   + its share of the inter-panel gateway bandwidth actually used per GPU
    #   (bw_gbps/G, one gateway port). pJ/bit: glass-FB blended 1.15, copper >=20
    #   (paper convention). Fat-tree/flat GPU has one NIC = its aggregate directly,
    #   so solve r such that r * 20 == glassfb_agg * 1.15 for the same power budget.
    calc_fair_speed() {
      local bw=$1 g=$2
      awk -v bw="$bw" -v g="$g" "BEGIN {
        elec=1800; opt=400
        agg_gbps = (elec + opt + bw/g) * 8
        power_w = agg_gbps * 1.15 * 0.001
        r_gbps = power_w / (20 * 0.001)
        speed_mbps = (r_gbps/8) * 8000
        printf \"%.0f %.2f %.4f\", speed_mbps, agg_gbps, power_w
      }"
    }

    run_topo() {
      local bin=$1 wl=$2 ep=$3 nodes=$4 bw=$5 g=$6 label=$7 speed_mbps=$8
      local pb=../../../experiments/pb_workloads/pb/${wl}_ep${ep}.pb
      local wm=../../../test/wm_ep${ep}.txt
      local log=./isopower_logs/${label}_${wl}_ep${ep}_bw${bw}_g${g}.log
      "$bin" -nodes $nodes -flowfile "$pb" -speed $speed_mbps -mtu 1500 -q 10000 -weightmatrix "$wm" > "$log" 2>&1
      local ps=$(grep "finished one iter" "$log" | tail -1 | grep -oE "now [0-9]+" | awk "{print \$2}")
      [ -z "$ps" ] && ps=0
      local ms=$(awk -v p=$ps "BEGIN{printf \"%.3f\", p/1e9}")
      local rto=$(grep -c "^At " "$log")
      echo "$wl,$ep,$nodes,$label,$bw,$g,$speed_mbps,$agg,$power,$ps,$ms,$rto" >> "$CSV"
      echo "done: $label $wl ep$ep bw$bw G$g speed=${speed_mbps}Mbps -> ${ms}ms rtos=$rto"
    }

    for bw in 400 800 1600; do
      for g in 1 4; do
        read speed agg power <<< "$(calc_fair_speed $bw $g)"
        echo "=== bw=$bw G=$g -> fair speed=${speed}Mbps (agg=${agg}Gb/s, power=${power}W) ==="
        for wl in decode coding_prefill chat_prefill agentic_prefill; do
          for ep in 32 64; do
            nodes=$ep
            run_topo ./htsim_tcp_fattree $wl $ep $nodes $bw $g fattree $speed
            run_topo ./htsim_tcp_flat $wl $ep $nodes $bw $g flat $speed
          done
        done
      done
    done
    echo "=== DONE, row count: $(($(wc -l < "$CSV") - 1)) ==="
  '
