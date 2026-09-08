#!/bin/bash
# Per-tier bytes for the 8x8 DSE arms, WITHOUT re-running any traffic.
#
# WHY NOT tier_bytes.sh. That script gets its hop classification from a full
# instrumented simulation under htsim_tcp_glassfb_pmhop with GLASS_LOG_HOPS=1.
# Two reasons it cannot serve here: the binary IS GONE from the tree (destroyed in
# one of the day's build incidents and never rebuilt), and it never carried the
# GLASS_MAXDIST gate anyway -- so the mesh arm would silently have been dumped as
# a second flattened butterfly, which is precisely the failure submit_batch10.sh
# refuses to allow.
#
# WHAT THIS DOES INSTEAD. glassfb_hopdump builds the same GlassFBTopology the
# runner builds and calls node_path() for each (src,dst) pair read on stdin,
# emitting the topology's OWN tier classification. It carries GLASS_MAXDIST, so
# the mesh arm is the mesh. hopdump_validate.sh already established that this dump
# is byte-identical to the hop log a real run emits at EP 16/32/64, and that it is
# invariant to GLASS_DIM_A2A and GLASS_EP_PLACE -- the tier split is a property of
# geometry and cabling, not of routing policy or placement.
#
# THE FLOW SET IS REUSED, AND THAT IS SOUND FOR A STATED REASON. The (src,dst,bytes)
# multiset comes from the task graph, not the fabric: ffapp emits the same flows
# whichever topology is loaded, and the intra-node shortcut is disabled in both.
# That was verified independently -- the glass EP=16 flow log has 78592 flows and
# the hgx8_pkt EP=16 FCT log has 78592 records. So a flow log captured at PANEL=16
# describes the same traffic at PANEL=64; only the hop CLASSIFICATION changes, and
# that is what is recomputed here.
#
# EP=128 IS NOT PRODUCED. There is no glass flow log at EP=128 -- tier_ep128 has a
# hoplog and no flowlog -- so bytes cannot be attributed to tiers at that EP by
# this method, and none is guessed.
set -uo pipefail
cd /storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter
PM=../../../experiments/portmaps
OUT=../../../experiments/results/paper/tier_bytes_dse.csv
BIN=./glassfb_hopdump
[ -x "$BIN" ] || { echo "FATAL: $BIN not built"; exit 1; }
[ "$(strings $BIN | grep -c GLASS_MAXDIST)" -ge 1 ] || { echo "FATAL: $BIN lacks GLASS_MAXDIST -- the mesh arm would be a butterfly"; exit 1; }
mkdir -p ./tier_logs/dse

echo "paper_ref,arm,grid,topo,ep,nodes,opt_bw_GBps,port_bw_GBps,maxdist,cabling,q,pairs,flows,bytes_total,bytes_x_hops_elec,bytes_x_hops_opt,bytes_x_hops_inter,hops_elec,hops_opt,hops_inter,source,note" > "$OUT"

one () { # arm maxdist ep nodes q
  local arm=$1 md=$2 ep=$3 nodes=$4 q=$5
  local fl=./tier_logs/tier_ep${ep}.flowlog
  if [ ! -s "$fl" ]; then echo "  SKIP ep=$ep: no flow log at $fl"; return 0; fi
  local hl=./tier_logs/dse/${arm}64_ep${ep}.hoplog
  GLASS_LOG_HOPS=1 GLASS_RTO_MIN_US=100 GLASS_PANEL=64 GLASS_PCOLS=8 \
  GLASS_ELEC_BW=1800 GLASS_OPT_BW=128 GLASS_PORT_BW=800 GLASS_MAXDIST="$md" \
  GLASS_EP_PLACE=1 GLASS_DIM_A2A=1 GLASS_PORT_MAP="$PM/p64_ep${ep}.txt" \
    $BIN -nodes "$nodes" -q "$q" < "$fl" 2>&1 >/dev/null | grep '^hoplog: ' > "$hl"
  local n; n=$(wc -l < "$hl")
  if [ "$n" -eq 0 ]; then echo "  FAILED ep=$ep $arm: hopdump emitted nothing"; return 0; fi
  python3 - "$arm" "$md" "$ep" "$nodes" "$q" "$fl" "$hl" "$OUT" <<'PY'
import sys, collections
arm, md, ep, nodes, q, flp, hlp, out = sys.argv[1:9]
hops = {}
for L in open(hlp):
    f = L.split()
    if len(f) >= 6:
        hops[(f[1], f[2])] = (int(f[3]), int(f[4]), int(f[5]))
bx = [0, 0, 0]; hsum = [0, 0, 0]; tot = 0; n = 0; missing = 0; carried_missing = 0
for L in open(flp):
    f = L.split()
    if len(f) < 4: continue
    k = (f[1], f[2]); b = int(f[3])
    h = hops.get(k)
    if h is None:
        # A pair with no route is only a defect if it CARRIES BYTES. The flow log
        # contains zero-byte dependency edges that never put a packet on a wire,
        # so the topology is never asked for their path -- 384 of them at EP=16,
        # three per node, carrying 0 bytes in total. Refusing on those would refuse
        # every EP for a reason that cannot move a single tier total. Refusing on a
        # byte-carrying one is the check that matters, and it is kept.
        missing += 1
        if b:
            carried_missing += 1
        continue
    n += 1; tot += b
    for i in range(3):
        bx[i] += b * h[i]
for k, h in hops.items():
    for i in range(3):
        hsum[i] += h[i]
if carried_missing:
    print("  !! ep=%s %s: %d flow(s) CARRYING BYTES had no routed pair -- NOT recorded"
          % (ep, arm, carried_missing))
    raise SystemExit
topo = "mesh" if md == "1" else "fb"
note = ("hop classification from glassfb_hopdump over the SAME topology the runner "
        "builds (GLASS_MAXDIST honoured); flow set reused from the EP-matched glass "
        "flow log, which is workload-determined and topology-independent (78592 flows "
        "at EP=16 matches the hgx8_pkt FCT record count); no traffic was re-simulated; "
        "%d zero-byte dependency flow(s) are unrouted and contribute nothing" % missing)
with open(out, "a") as fh:
    fh.write("dse,%s,8x8,%s,%s,%s,128,800,%s,p64_ep%s.txt,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,glassfb_hopdump,\"%s\"\n"
             % (arm, topo, ep, nodes, md, ep, q, len(hops), n, tot,
                bx[0], bx[1], bx[2], hsum[0], hsum[1], hsum[2], note))
print("  %-5s ep=%-4s pairs=%-6d flows=%-7d bytes=%.3f TB | elec %.3f  opt %.3f  inter %.3f TB-hops"
      % (arm, ep, len(hops), n, tot/1e12, bx[0]/1e12, bx[1]/1e12, bx[2]/1e12))
PY
}

echo "### 8x8 flattened butterfly (MAXDIST=0)"
one fb   0 16 128  2133
one fb   0 32 256  8533
one fb   0 64 512  8533
echo "### 8x8 mesh (MAXDIST=1)"
one mesh 1 16 128  4267
one mesh 1 32 256  8533
one mesh 1 64 512  8533
echo
echo "wrote $OUT"
column -s, -t "$OUT" 2>/dev/null | cut -c1-165
