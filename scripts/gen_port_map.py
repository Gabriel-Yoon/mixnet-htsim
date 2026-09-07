#!/usr/bin/env python3
"""Generate a Glass-FB inter-panel PORT MAP from a job's parallelism layout.

A panel has one MTP-16 optical port per GPU (16 for a 4x4). The map assigns those ports to
the panel's LOGICAL neighbours so every collective's cross-panel path is one hop:
  EP partner panel(s)  : expert all-to-all  (heavy)     -> --ep-ports, shared equally
  DP replica panel(s)  : gradient all-reduce (ring: dp-1 neighbours; a pair for dp=2)
  PP prev / next panel : pipeline activations (light)
Logical rank order is the one the FlexFlow/LLMServingSim graphs use, with tp fastest,
then ep, then a combined (dp,pp) index `hi`:  n = (hi*ep + ep_idx)*tp + tp_idx.
--hi-order says whether hi = dp_idx*pp + pp_idx (dp_major, default) or pp_idx*dp + dp_idx.
VERIFY --hi-order against the task graph's all-reduce pairs before trusting a map.
Placement is the topology's EP-aware phys():  phys(n) = ((hi*tp + tp_idx)*ep + ep_idx),
i.e. EP-mates contiguous; panel = phys // psize.  Output lines: "p q n" (symmetric).

Example: python3 gen_port_map.py --dp 2 --tp 1 --pp 4 --ep 32 --psize 16 \
             --ep-ports 12 --dp-ports 2 --pp-ports 1 -o portmap_ep32_12_2_1.txt
"""
import argparse, collections, sys

ap = argparse.ArgumentParser()
ap.add_argument("--dp", type=int, required=True); ap.add_argument("--tp", type=int, default=1)
ap.add_argument("--pp", type=int, required=True); ap.add_argument("--ep", type=int, required=True)
ap.add_argument("--psize", type=int, default=16)
ap.add_argument("--ep-ports", type=int, default=12, help="ports per panel for ALL its EP partners together")
ap.add_argument("--dp-ports", type=int, default=2, help="ports per panel for ALL its DP ring neighbours together")
ap.add_argument("--pp-ports", type=int, default=1, help="ports per PP neighbour (prev and next each)")
ap.add_argument("--hi-order", choices=["dp_major", "pp_major"], default="dp_major")
ap.add_argument("--no-ep-place", action="store_true", help="naive placement (phys = logical)")
ap.add_argument("-o", "--out", default="-")
a = ap.parse_args()

dp, tp, pp, ep, ps = a.dp, a.tp, a.pp, a.ep, a.psize
N = dp * tp * pp * ep
P = N // ps
assert N % ps == 0, "nodes must be a multiple of psize"

def hi_of(d, s):  return d * pp + s if a.hi_order == "dp_major" else s * dp + d
def logical(d, s, e, t): return (hi_of(d, s) * ep + e) * tp + t
def phys(n):
    if a.no_ep_place or ep <= 1: return n
    hi = n // (ep * tp); e = (n // tp) % ep; t = n % tp
    return (hi * tp + t) * ep + e
def panel(n): return phys(n) // ps

# neighbour panels per class, per panel
nb = {p: {"ep": set(), "dp": set(), "pp": set()} for p in range(P)}
for d in range(dp):
    for s in range(pp):
        for e in range(ep):
            for t in range(tp):
                p = panel(logical(d, s, e, t))
                for e2 in range(ep):                       # EP partners (same d,s,t)
                    q = panel(logical(d, s, e2, t))
                    if q != p: nb[p]["ep"].add(q)
                for d2 in ((d + 1) % dp, (d - 1) % dp):    # DP ring neighbours
                    if d2 != d:
                        q = panel(logical(d2, s, e, t))
                        if q != p: nb[p]["dp"].add(q)
                for s2 in (s - 1, s + 1):                  # PP prev / next
                    if 0 <= s2 < pp:
                        q = panel(logical(d, s2, e, t))
                        if q != p: nb[p]["pp"].add(q)

pm = collections.defaultdict(int)
def give(p, q, n):
    if n <= 0: return
    key = (min(p, q), max(p, q))
    pm[key] = max(pm[key], n)      # symmetric; classes may overlap (e.g. dp==ep partner) -> take max

for p in range(P):
    eps, dps, pps = sorted(nb[p]["ep"]), sorted(nb[p]["dp"]), sorted(nb[p]["pp"])
    if eps:
        base, extra = divmod(a.ep_ports, len(eps))
        for i, q in enumerate(eps): give(p, q, base + (1 if i < extra else 0))
    if dps:
        base, extra = divmod(a.dp_ports, len(dps))
        for i, q in enumerate(dps): give(p, q, base + (1 if i < extra else 0))
    for q in pps: give(p, q, a.pp_ports)

used = collections.Counter()
for (p, q), n in pm.items(): used[p] += n; used[q] += n
worst = max(used.values()) if used else 0
lines = [f"# gen_port_map.py dp={dp} tp={tp} pp={pp} ep={ep} psize={ps} hi_order={a.hi_order} "
         f"ep_ports={a.ep_ports} dp_ports={a.dp_ports} pp_ports={a.pp_ports}",
         f"# panels={P} ports used per panel: min {min(used.values()) if used else 0} max {worst} of {ps}"]
for p in range(P):
    lines.append(f"# panel {p}: ep->{sorted(nb[p]['ep'])} dp->{sorted(nb[p]['dp'])} pp->{sorted(nb[p]['pp'])} used {used[p]}")
for (p, q), n in sorted(pm.items()): lines.append(f"{p} {q} {n}")
out = "\n".join(lines) + "\n"
if a.out == "-": sys.stdout.write(out)
else: open(a.out, "w").write(out)
if worst > ps:
    sys.exit(f"ERROR: panel needs {worst} ports > {ps}; lower --ep-ports/--dp-ports/--pp-ports")
print(f"ok: {P} panels, {len(pm)} pairs, ports per panel <= {worst}/{ps}", file=sys.stderr)
