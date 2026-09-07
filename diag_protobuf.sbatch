#!/bin/bash
#SBATCH --job-name=diag-pb
#SBATCH --account=gts-syu334-ece
#SBATCH --partition=cpu-small
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --output=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_diagpb_%j.out
#SBATCH --error=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/slurm_diagpb_%j.err

export APPTAINER_CACHEDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_cache
export APPTAINER_TMPDIR=/storage/home/hcoda1/8/syoon351/scratch/apptainer_tmp
SIF=/storage/project/r-syu334-0/shared/images/astra-sim_latest.sif

apptainer exec --cleanenv "$SIF" bash -c '
  echo "=== files in /opt/protobuf-29.0/install/lib ==="
  ls -la /opt/protobuf-29.0/install/lib/ | grep -i proto
  echo "=== symbol presence in libprotobuf.a ==="
  nm /opt/protobuf-29.0/install/lib/libprotobuf.a 2>/dev/null | grep -i ReportReflectionUsageError
  echo "=== T=defined t=local-defined U=undefined count ==="
  nm /opt/protobuf-29.0/install/lib/libprotobuf.a 2>/dev/null | grep -i ReportReflectionUsageError | awk "{print \$2}" | sort | uniq -c
  echo "=== gcc version ==="
  g++ --version | head -1
  echo "=== check for LTO / bytecode section in the relevant .o ==="
  ar t /opt/protobuf-29.0/install/lib/libprotobuf.a | grep generated_message_reflection
  ar p /opt/protobuf-29.0/install/lib/libprotobuf.a generated_message_reflection.cc.o > /tmp/gmr.o 2>/dev/null
  file /tmp/gmr.o
  readelf -S /tmp/gmr.o 2>/dev/null | grep -i lto
  echo "=== conda env protobuf ==="
  ls -la /storage/scratch1/8/syoon351/conda/envs/llmservingsim/lib/ | grep -i protobuf
'
