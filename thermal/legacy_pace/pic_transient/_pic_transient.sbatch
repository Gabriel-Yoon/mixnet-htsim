#!/bin/bash
#SBATCH -J pic_transient
#SBATCH -A gts-syu334-ece
#SBATCH -q inferno
#SBATCH -N1 -n8
#SBATCH --mem=16G
#SBATCH -t2:00:00
#SBATCH -o /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/thermal_pic/_sbatch_pic_transient.out
#SBATCH -e /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/thermal_pic/_sbatch_pic_transient.err
cd /storage/home/hcoda1/8/syoon351/scratch/repos/mixnet-sim/thermal_pic
module load ansys/2025R2
rm -f *.lock
date
ansys252 -b -j pic_mixtral -np 8 -smp -i pic_transient_mixtral8x7b.inp -o _out_mixtral.out
grep -q 'NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0' _out_mixtral.out && echo 'mixtral OK (0 errors)' || echo 'mixtral HAD ERRORS'
date
ansys252 -b -j pic_llama -np 8 -smp -i pic_transient_llamamoe.inp -o _out_llama.out
grep -q 'NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0' _out_llama.out && echo 'llama OK (0 errors)' || echo 'llama HAD ERRORS'
date
ls -la *.csv
echo PIC_TRANSIENT_DONE
