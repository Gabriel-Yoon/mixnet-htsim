#!/bin/bash
# Complete cross-panel used-pair sets, from every collective rather than the
# all-to-all alone.
#
# WHY THIS EXISTS. The port maps were to be regenerated from a flow log derived
# from ffapp's "flow_size:" print. That print occurs at exactly ONE site --
# inside the all-to-all -- while set_flowsize() is called from NINE. Every DP
# all-reduce and PP point-to-point flow therefore moved, routed and relayed
# while printing nothing. A map built from that log would cable the 8 EP pairs,
# leave every DP and PP pair to relay, and still look complete and internally
# consistent. So the log is taken at the choke point instead: TcpSrc::set_flowsize,
# which every collective reaches, guarded by GLASS_LOG_FLOWS.
#
# Runs use htsim_tcp_glassfb_pmlog, a separate link target, so the running
# pm-cliff sweep keeps spawning the untouched htsim_tcp_glassfb_pm.
#
# Config is identical to the pm-cliff rows the maps are for. Each set is written
# as soon as its run finishes, so EP=32 is available without waiting for EP=128.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
R=/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results
T=../../../test; PM=../../../experiments/portmaps
OUT=$PM/usedpairs
BIN=./htsim_tcp_glassfb_pmlog
PSIZE=16
mkdir -p "$OUT" ./fl_logs

# Fail loudly rather than silently producing an all-to-all-only set again.
if [ "$(strings $BIN | grep -c GLASS_LOG_FLOWS)" -eq 0 ]; then
  echo "FATAL: $BIN has no GLASS_LOG_FLOWS instrumentation -- wrong binary"; exit 1
fi

row () { # tag nodes fbuf wm map tmo
  local tag=$1 nodes=$2 fb=$3 wm=$4 map=$5 tmo=$6
  local log=./fl_logs/${tag}.log fl=./fl_logs/${tag}.flowlog t0 t1
  t0=$(date +%s)
  GLASS_LOG_FLOWS=1 \
  GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/$map" \
    timeout "$tmo" $BIN -nodes "$nodes" -flowfile "$R/$fb" \
      -disable-intra-shortcut -mtu 1500 -q 1064 -weightmatrix "$T/$wm" > "$log" 2>&1
  local rc=$?; t1=$(date +%s)
  grep "^flowlog: " "$log" > "$fl"

  local nflow comp
  nflow=$(wc -l < "$fl")
  [ "$rc" = "124" ] && comp=TRUNCATED || comp=COMPLETE

  # A truncated run gives a PARTIAL pair set, which is exactly the failure this
  # script exists to avoid. Mark it in the filename so it cannot be mistaken.
  local suffix=""; [ "$comp" = TRUNCATED ] && suffix=".PARTIAL"

  awk -v ps="$PSIZE" '
    { p = int($2/ps); q = int($3/ps); if (p == q) next;
      a = p < q ? p : q; b = p < q ? q : p;
      bytes[a" "b] += $4; nf[a" "b]++ }
    END { for (k in bytes) printf "%s %.0f %d\n", k, bytes[k], nf[k] }
  ' "$fl" | sort -k3,3 -rn > "$OUT/${tag}.pairs${suffix}"

  local npair total
  npair=$(wc -l < "$OUT/${tag}.pairs${suffix}")
  total=$(awk '{s+=$3} END{printf "%.3f", s/1e12}' "$OUT/${tag}.pairs${suffix}")
  printf "  %-16s %-10s flows=%-9s cross-panel pairs=%-5s inter TB=%-9s wall=%ss -> %s\n" \
    "$tag" "$comp" "$nflow" "$npair" "$total" "$((t1-t0))" "${tag}.pairs${suffix}"
  echo "     top pairs (p q bytes nflows):"
  head -8 "$OUT/${tag}.pairs${suffix}" | sed 's/^/       /'
}

L16=llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100.fbuf
L32=llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100.fbuf
QME=qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100.fbuf
Q57=qwen2_57b_paper_dp2tp1pp4_ep64top8_L4_seq1024_mb8_H100.fbuf
ARC=arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100.fbuf

echo "########## EP=16 -- validation: its map already relays 0, so its pair set must be coverable ##########"
row fl_ep16      128 "$L16" wm_ep16.txt  ep16_0_8_4.txt   1800
echo "########## EP=32 -- the map that still relays (13,15) ##########"
row fl_ep32      256 "$L32" wm_ep32.txt  ep32_12_2_1.txt  7200
echo "########## EP=64 ##########"
row fl_ep64_qme  512 "$QME" wm_ep64.txt  ep64_12_2_1.txt  25200
row fl_ep64_q57  512 "$Q57" wm_ep64.txt  ep64_12_2_1.txt  25200
echo "########## EP=128 ##########"
row fl_ep128_arc 1024 "$ARC" wm_ep128.txt ep128_12_1_1.txt 36000

echo "=== DONE ==="
ls -la "$OUT"
