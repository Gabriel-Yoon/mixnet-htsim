#!/usr/bin/env python3
"""SUPERSEDED -- DO NOT USE. Produces a silently partial pair set.

This reads ffapp's "flow_size:" print, which exists at ONE site (inside the
all-to-all) while set_flowsize() is called from nine. It therefore reports the
EP pairs and omits every DP and PP flow: at EP=32 it returned 8 pairs where the
workload actually touches 36, and the map built from it left (13,15) -- a DP
pair -- relaying.

Use scripts/flowlog_pairs.sh, which records at TcpSrc::set_flowsize under
GLASS_LOG_FLOWS, the one choke point every collective passes through.

Kept only so the provenance record (docs/methods_provenance.md, sub-class F)
points at real code.
"""
"""Complete cross-panel used-pair set from a COMPLETED run's flow log.

Every flow the simulator creates prints "flow_size: N src_node: X dst_node: Y",
so a completed run's log is the full communication set -- not just the pairs that
happened to relay. With tp=1, phys(n)=n, so panel = n // psize.

Only valid on a COMPLETED run: a truncated one has not started every task, and a
missing pair would silently become an uncabled pair later.
"""
import re, sys, collections
log, psize = sys.argv[1], int(sys.argv[2])
FLOW = re.compile(r"flow_size:\s*(\d+)\s+src_node:\s*(\d+)\s+dst_node:\s*(\d+)")
pairs = collections.Counter()
nflow = collections.Counter()
n = 0
for line in open(log, errors="ignore"):
    m = FLOW.search(line)
    if not m:
        continue
    b, s, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    n += 1
    ps, pd = s // psize, d // psize
    if ps == pd:
        continue
    key = (min(ps, pd), max(ps, pd))
    pairs[key] += b
    nflow[key] += 1
sys.stderr.write(f"# {log}: {n} flows, {len(pairs)} cross-panel pairs\n")
for (p, q), b in sorted(pairs.items(), key=lambda kv: -kv[1]):
    print(f"{p} {q} {b}")
