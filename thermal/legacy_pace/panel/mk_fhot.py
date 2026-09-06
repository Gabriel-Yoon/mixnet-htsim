s = open("run_panel_cal.sh").read()
s = s.replace('OUT=panel_cal_tiles.csv', 'OUT=panel_fhot_tiles.csv')
s = s.replace('local v=$1 mf=$2 pj=$3 hcp=$4 tin=$5 pi=$6 pe=$7 pc=$8 pt=$9 plane=${10}',
              'local v=$1 mf=$2 pj=$3 hcp=$4 tin=$5 pi=$6 pe=$7 pc=$8 pt=$9 plane=${10} fh=${11:-0.5}')
s = s.replace('echo "FHOT=0.5"', 'echo "FHOT=$fh"')
i = s.index('echo "### 1. cold-plate calibration')
tail = (
 'echo "### hotspot-fraction sensitivity at the calibrated plate ###"\n'
 'echo "   FHOT=0.5 is our assumption, not a measurement; 0.25/0.35 bracket it."\n'
 'run cal_fhot0p25_h200k_tin40 1 1.15 200000 40 14.1 35.9 57.7 1.44 "" 0.25\n'
 'run cal_fhot0p35_h200k_tin40 1 1.15 200000 40 14.1 35.9 57.7 1.44 "" 0.35\n'
 'run cal_fhot0p50_h200k_tin40 1 1.15 200000 40 14.1 35.9 57.7 1.44 "" 0.50\n'
 'echo "=== DONE ==="\n'
 'echo "=== outlet tile, die and PIC vs hotspot fraction ==="\n'
 "awk -F, 'NR>1 && $7==3 && $8==3 {printf \"  %-30s die=%9s pic=%9s\\n\", $2, $14, $11}' \"$OUT\"\n"
)
open("run_panel_fhot.sh", "w").write(s[:i] + tail)
print("wrote run_panel_fhot.sh")
