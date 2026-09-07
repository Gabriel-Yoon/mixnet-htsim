#!/bin/bash
#SBATCH --job-name=pkt128
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-medium
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=180G
#SBATCH --time=24:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_p128_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_p128_%j.err

set -uo pipefail

bash /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/pkt_ep128.sh
