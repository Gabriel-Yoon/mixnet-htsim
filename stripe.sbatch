#!/bin/bash
#SBATCH --job-name=stripe
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-medium
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_stripe_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_stripe_%j.err

set -uo pipefail

bash /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/scripts/stripe_control.sh
