#!/bin/bash
#SBATCH -J pic_transient_v2
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=16G
#SBATCH -t2:00:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/thermal_pic/_sbatch_pic_v2.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/thermal_pic/_sbatch_pic_v2.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/thermal_pic
module load ansys/2025R2
rm -f *.lock
date
ansys252 -b -j pic_mixtral_v2 -np 8 -smp -i pic_transient_mixtral8x7b_v2.inp -o _out_mixtral_v2.out
grep -q 'NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0' _out_mixtral_v2.out && echo 'mixtral OK (0 errors)' || echo 'mixtral HAD ERRORS'
ansys252 -b -j pic_llama_v2 -np 8 -smp -i pic_transient_llamamoe_v2.inp -o _out_llama_v2.out
grep -q 'NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0' _out_llama_v2.out && echo 'llama OK (0 errors)' || echo 'llama HAD ERRORS'
date
ls -la *_v2.csv
echo PIC_V2_DONE
