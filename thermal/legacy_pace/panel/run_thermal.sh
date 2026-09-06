#!/bin/bash
# Driver for the glass-photonic FB package thermal study (ANSYS MAPDL, batch, no GUI).
# Produces the three deliverables:
#   T1  steady baseline (chosen design)         -> thermal_steady.csv (one row)
#   T3  design sweep TGV pitch x material        -> thermal_steady.csv (many rows)
#   T2  transient GPU step, glass vs silicon     -> transient_glass.csv / transient_si.csv
#
# RUN ON HPC (login node is fine for these small models; or an interactive/batch node):
#   module load ansys/2025R2
#   bash run_thermal.sh
# Each case launches a fresh MAPDL: robust + license-clean. ~seconds per case.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
MAPDL="${MAPDL:-ansys252}"      # from `module load ansys/2025R2`
NP="${NP:-4}"

export ANSYS_LOCK=OFF           # avoid stale .lock collisions across cases
rm -f ./*.lock 2>/dev/null

run_case () {   # writes a case wrapper that *SETs params then /INPUTs the body, runs MAPDL
  local body="$1"; local tag="$2"; shift 2
  local wrap="_case_${tag}.inp"
  { for kv in "$@"; do echo "$kv"; done
    echo "CASETAG='$tag'"
    echo "/INPUT,${body},inp"
  } > "$wrap"
  echo "  [MAPDL] $tag"
  "$MAPDL" -b -j "job_${tag}" -np "$NP" -smp -i "$wrap" -o "_out_${tag}.out" >/dev/null 2>&1
  if ! grep -q "NUMBER OF ERROR   MESSAGES ENCOUNTERED=          0" "_out_${tag}.out" 2>/dev/null; then
    echo "    !! MAPDL error in $tag (see _out_${tag}.out)"
  fi
}

# ---- fresh result files ----
: > thermal_steady.csv
echo "matflag,pitch_um,ksub_z,pgpu_w,ppic_w,tpic_max_C,dT_array_K,tdie_max_C,ptrim_W" >> thermal_steady.csv

# ---- T1 + T3 : steady sweep --------------------------------------------------
# chosen design point + a TGV-pitch sweep x {glass, silicon-control}, at full TDP.
PGPU=700       # H100-class die power [W]   (use 1000 for B200-class)
PPIC=25        # PIC power (modulators + ring trim) [W]
TCP=60         # cold-plate coolant [C]
HCP=70000     # cold-plate effective convection [W/m^2K] (direct-liquid microchannel): Si
              # microchannel HTC, CFD-derived (Coenen et al., IEEE TCPMT 2026, "Benchmarking
              # the Thermal Impact of 2.5D/3D Co-Packaged Optics on Si Photonic Devices")
for MAT in 1 0; do                       # 1=glass, 0=silicon control
  for PITCH in 100 150 200 300 400 500; do   # TGV pitch [um]
    lbl="mat${MAT}_p${PITCH}"
    run_case thermal_body "$lbl" \
      "MATFLAG=$MAT" "PITCH_UM=$PITCH" "PGPU_W=$PGPU" "PPIC_W=$PPIC" \
      "TCP_C=$TCP" "HCP=$HCP" "CSVOUT='thermal_steady.csv'"
  done
done
echo "T1/T3 done -> thermal_steady.csv"

# ---- T2 : transient GPU power step, glass vs silicon -------------------------
# step idle(200W) -> TDP(700W); watch PIC-center temperature response.
PIDLE=200; TEND=60; DTS=0.5
PITCH_T=200                              # chosen TGV pitch for the transient
run_case thermal_transient_body glass_tr \
  "MATFLAG=1" "PITCH_UM=$PITCH_T" "PGPU_W=$PGPU" "PPIC_W=$PPIC" \
  "TCP_C=$TCP" "HCP=$HCP" "PIDLE_W=$PIDLE" "TEND_S=$TEND" "DT_S=$DTS" \
  "CSVOUT='transient_glass'"
run_case thermal_transient_body si_tr \
  "MATFLAG=0" "PITCH_UM=$PITCH_T" "PGPU_W=$PGPU" "PPIC_W=$PPIC" \
  "TCP_C=$TCP" "HCP=$HCP" "PIDLE_W=$PIDLE" "TEND_S=$TEND" "DT_S=$DTS" \
  "CSVOUT='transient_si'"
echo "T2 done -> transient_glass.csv / transient_si.csv"

echo "ALL DONE. Plot with: python3 plot_thermal.py"
