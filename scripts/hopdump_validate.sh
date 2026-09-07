#!/bin/bash
# Validate glassfb_hopdump against the hop logs the real tier runs emitted.
#
# The dump builds the same GlassFBTopology the runner builds and calls get_paths
# for each pair in the flow log, so the topology emits its own hoplog lines. The
# claim being tested is that node_path() is a pure function of (src, dest) and the
# configuration -- no dependence on traffic, on timing, or on the order pairs are
# asked for. If that is false, these diffs fail.
#
# RED first, at EP=16 with GLASS_PORT_MAP unset: the fabric falls back from the
# cabled port map to the default 2-level FB, which changes which intra-panel legs
# a cross-panel flow takes to reach its gateway. A check that has not been seen to
# fail is not a check.
#
# TWO PERTURBATIONS THAT DID NOT MOVE IT, recorded because a red test that passes
# proves only that the perturbation was not one:
#
#   GLASS_DIM_A2A=0   IDENTICAL. Dimension-ordered routing chooses between
#                     intra_relay() and intra_relay2() for the middle node of a
#                     2-hop intra-panel path, and both give that path the same
#                     tier composition. It changes which links carry the bytes,
#                     not how many hops of each tier they cross.
#   GLASS_EP_PLACE=0  IDENTICAL, and necessarily so. Placement decides which RANK
#                     sits on which node; this dump is driven by (src, dst) NODE
#                     ids straight out of the flow log, so the placement is
#                     already baked into the input and cannot change the routing
#                     of a given node pair.
#
# Both of those are worth knowing on their own: the tier split is a property of
# the topology's geometry and cabling, not of the routing policy within a panel
# or of where the ranks were placed.
set -uo pipefail
cd "$(dirname "$0")/../src/clos/datacenter"
PM=../../../experiments/portmaps
BIN=./glassfb_hopdump
[ -x "$BIN" ] || { echo "FATAL: $BIN not built (make glassfb_hopdump)"; exit 1; }

dump () { # out env... -- nodes q flowlog
  local out=$1; shift
  local nodes=$1 q=$2 fl=$3 map=$4 dim=$5
  GLASS_LOG_HOPS=1 GLASS_RTO_MIN_US=100 GLASS_PANEL=16 GLASS_ELEC_BW=1800 \
  GLASS_OPT_BW=384 GLASS_EP_PLACE=1 GLASS_DIM_A2A="$dim" GLASS_PORT_MAP="$PM/$map" \
    $BIN -nodes "$nodes" -q "$q" < "$fl" 2>&1 >/dev/null | grep '^hoplog: ' > "$out"
}

dump_nomap () { # out nodes q flowlog -- same, with the cabling removed
  local out=$1 nodes=$2 q=$3 fl=$4
  env -u GLASS_PORT_MAP GLASS_LOG_HOPS=1 GLASS_RTO_MIN_US=100 GLASS_PANEL=16 \
      GLASS_ELEC_BW=1800 GLASS_OPT_BW=384 GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 \
    $BIN -nodes "$nodes" -q "$q" < "$fl" 2>&1 >/dev/null | grep '^hoplog: ' > "$out"
}

cmp_tiers () { # label flowlog mine ref
  python3 - "$@" <<'EOF'
import collections, sys
label, flowlog, mine_p, ref_p = sys.argv[1:5]
def load(p):
    h = {}
    for l in open(p):
        f = l.split()
        if len(f) == 6:
            h[(int(f[1]), int(f[2]))] = (int(f[3]), int(f[4]), int(f[5]))
    return h
def tiers(h):
    t, miss = collections.Counter(), 0
    for l in open(flowlog):
        f = l.split()
        s, d, b = int(f[1]), int(f[2]), int(f[3])
        if b == 0:
            continue
        v = h.get((s, d))
        if v is None:
            miss += 1; continue
        t['elec'] += b * v[0]; t['opt'] += b * v[1]; t['inter'] += b * v[2]
    return t, miss
mine, ref = load(mine_p), load(ref_p)
shared = set(mine) & set(ref)
bad = [k for k in shared if mine[k] != ref[k]]
tm, mm = tiers(mine); tr, mr = tiers(ref)
same = (tm == tr and mm == mr and not bad)
print("  %-10s pairs mine=%-6d ref=%-6d shared=%-6d hop-triple disagreements=%d"
      % (label, len(mine), len(ref), len(shared), len(bad)))
print("             elec/opt/inter  mine %d / %d / %d" % (tm['elec'], tm['opt'], tm['inter']))
print("                             ref  %d / %d / %d" % (tr['elec'], tr['opt'], tr['inter']))
print("             unmatched-by-hoplog flows: mine=%d ref=%d" % (mm, mr))
print("             ==> %s" % ("IDENTICAL" if same else "DIFFERS"))
sys.exit(0 if same else 1)
EOF
}

echo "########## RED: EP=16 with no port map (must DIFFER) ##########"
dump_nomap /tmp/hd16_red.hoplog 128 1064 tier_logs/tier_ep16.flowlog
if cmp_tiers ep16-red tier_logs/tier_ep16.flowlog /tmp/hd16_red.hoplog tier_logs/tier_ep16.hoplog; then
  echo "  FATAL: the check passed with the WRONG routing -- it cannot detect anything"; exit 1
else
  echo "  good: the check fails when the configuration is wrong"
fi

fail=0
echo "########## GREEN ##########"
dump /tmp/hd16.hoplog 128 1064  tier_logs/tier_ep16.flowlog ep16_0_8_4.txt 1
cmp_tiers ep16 tier_logs/tier_ep16.flowlog /tmp/hd16.hoplog tier_logs/tier_ep16.hoplog || fail=1
dump /tmp/hd32.hoplog 256 2133  tier_logs/tier_ep32.flowlog ep32_gt.txt 1
cmp_tiers ep32 tier_logs/tier_ep32.flowlog /tmp/hd32.hoplog tier_logs/tier_ep32.hoplog || fail=1
dump /tmp/hd64.hoplog 512 17067 tier_logs/tier_ep64.flowlog ep64_gt.txt 1
cmp_tiers ep64 tier_logs/tier_ep64.flowlog /tmp/hd64.hoplog tier_logs/tier_ep64.hoplog || fail=1

echo
if [ $fail -eq 0 ]; then
  echo "=== VALIDATED: the dump reproduces the real runs' tier bytes exactly at EP 16, 32 and 64 ==="
else
  echo "=== FAILED: do not use the dump at EP=128 ==="; exit 1
fi
