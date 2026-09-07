#!/bin/bash
#SBATCH --job-name=g64tail
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-medium
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=8:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_g64t_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_g64t_%j.err

set -uo pipefail

bash /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/ep64_tail.sh
