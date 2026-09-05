# Multi-Gateway EP>Panel Routing

Design notes for the method that fixes the EP>panel inter-panel congestion
collapse in Glass-FB, written up for eventual inclusion in the paper's
"beyond one panel" section. This is a design record, not paper prose — kept
here so the idea and its derivation survive independently of when the paper
text itself gets written.

## 1. The problem

When an expert-parallel (EP) group spans more than one 16-GPU panel, every
EP-mate flow between the two panels was routed through **one fixed gateway
GPU pair** (`glassfb_topology.cpp`'s original `node_path()`:
`{src, gw(p,q), gw(q,p), dest}`, one specific `gw(p,q)` per panel pair). For
EP=32 split across two panels, all 16x16 = 256 expert-parallel flows
converge on that single physical fiber — a textbook incast, independent of
how much bandwidth that one fiber has. Measured effect: at 800 GB/s
inter-panel bandwidth, this produced a **non-monotonic** bandwidth/latency
curve (106ms at 800GB/s, worse than both 400GB/s and 1600GB/s) driven by
synchronized TCP retransmission-timeout waves on the shared link.

The naive fix — just provision more bandwidth on that one link — works
(confirmed: 8x bandwidth removes the collapse) but isn't a *method*; it's
brute force, and the "beyond one panel" section needs an actual placement/
routing answer, the way Mozart or DeepEP have one for their own architectures.

## 2. Where the idea came from

Three independent threads converged on the same design:

- **DeepEP** (DeepSeek-V3's production expert-parallel library) routes
  scale-out traffic through a **same-index proxy**: a GPU on the remote node
  receives the combined inter-node transfer over its scale-out link (IB),
  then re-distributes it to the actual destination GPUs on that node over
  the fast local link (NVLink) — i.e., don't let a single link absorb all
  of a node's remote fan-in; give it dedicated proxies and let local
  bandwidth handle the last hop. The panel/gateway split (long optical hop,
  then short intra-panel relay) already mirrors this shape; the missing
  piece was *using more than one proxy per panel pair*.
- **ECMP / Valiant load balancing** — the standard networking answer to "one
  path is a hotspot, and I have several equally-good paths": hash flows
  across the available paths so no single path carries the whole load. The
  codebase already had a working precedent for exactly this idea one level
  down: `_dim_route` spreads each two-hop *intra*-panel relay across two
  possible corner relays by a hash of `(src, dst)`, specifically so a skewed
  MoE all-to-all doesn't pile onto one relay GPU. Multi-gateway routing is
  the same idea applied one level up, to the *inter*-panel hop.
- **MPO/MTP breakout cables** (real datacenter optics practice) — a
  multi-fiber trunk cable's individual strands don't have to all terminate
  at one transceiver; a breakout cable fans them out to several smaller
  transceivers on several different chips. This gave the physical
  justification for why "more gateway GPUs, same total fiber count" is a
  real hardware option and not just a simulator abstraction: split the same
  provisioned fiber bundle across several panel-edge GPUs instead of
  concentrating it on one.

## 3. The physical constraint that shaped the final design

An early version treated a panel's 16 GPUs as a free-floating pool: reserve
`G` slots per destination panel, `G * (number of neighbor panels) <= 16`.
This is wrong. A panel is a physical rectangle with **at most 4 edges**
(one per compass direction), and only the GPUs sitting on a given edge (one
full row or column of the panel's own 4x4 grid — 4 GPUs) can physically host
a fiber facing that direction; the interior 2x2 = 4 GPUs touch no edge at
all and can host no inter-panel fiber in any direction. So:

- A panel has **at most 4 physical neighbors**, not an arbitrary degree.
- Each of those 4 edges is an **independent, disjoint 4-GPU pool** — using
  all 4 slots on the north edge does not compete with the east edge's slots.
- Therefore `G <= 4` **unconditionally**, regardless of how many of the
  panel's other edges are also active — not `G <= panel_size / degree` as
  the free-pool version assumed.

This matches the paper's own stated hardware description (4 physical edges
per panel) exactly, and it's *more* physically plausible than the original
single-gateway design in one respect: concentrating an entire multi-fiber
bundle's worth of optical I/O on one GPU (today's design) demands a bigger
optical bump-budget on that one GPU than its neighbors; spreading it across
up to 4 GPUs per edge is more uniform.

## 4. The method

**Placement** (unchanged from the existing EP-aware placement): EP-mates are
relabeled so a 64-GPU EP domain occupies exactly 4 contiguous physical
panels. In an 8x4 panel grid this domain lands on one full grid row, whose
4 panels are then mutually adjacent under the mesh connectivity rule below.

**Topology** (`GLASS_INTER=mesh`, `glassfb_topology.h/.cpp`): a panel
connects only to its immediate N/S/E/W neighbors in the panel grid (not
"everyone in my row or column," which has no 4-edge realization). Each
direction is backed by a fixed 4-GPU edge pool: local index `g` on the edge
facing direction `dir` is

```
edge_local(dir, g) =
    row 0,                        col = g            if dir == N
    row (rows-1),                 col = g            if dir == S
    row = g,                      col (cols-1)       if dir == E
    row = g,                      col = 0            if dir == W
```

**Routing, single hop (adjacent panels)**: for a flow from `src` (panel `p`)
to `dst` (panel `q`), pick gateway slot

```
g = (loc(src) + loc(dst)) % G
```

— a **symmetric** hash of the two endpoints' in-panel local indices, so a
flow and its ACKs (which swap src/dst) always land on the same physical
gateway pair. Route: `src -> [intra-panel relay if src isn't already on
gw(p,q,g)] -> gw(p,q,g) -> gw(q,p,g) -> [intra-panel relay if needed] ->
dst`. Reusing the existing relay-insertion logic (`relay_for()`) for the
intra-panel legs means this is a small, local change to the topology's
routing table, not a new routing algorithm end to end.

**Routing, multi-hop (non-adjacent panels)**: build the panel-level path by
XY (row-then-column) dimension-order routing, then apply the single-hop
rule at each step:

```
panel_path(p, q):
    path = [p]
    while col(path.last) != col(q):
        step toward q's column (one panel, same row)
        append to path
    while row(path.last) != row(q):
        step toward q's row (one panel, same column)
        append to path
    return path

node_path(src, dst):
    p, q = panel(src), panel(dst)
    g = (loc(src) + loc(dst)) % G
    if p == q: return [src, dst]
    if adjacent(p, q): return [src, gw(p,q,g), gw(q,p,g), dst]
    pp = panel_path(p, q)
    wp = [src]
    for (a, b) in consecutive_pairs(pp):
        wp += [gw(a,b,g), gw(b,a,g)]
    wp += [dst]
    return wp   # intra-panel relays inserted automatically at same-panel,
                # non-directly-linked consecutive waypoints
```

**Bandwidth**: the panel pair's total inter-panel bandwidth is divided by
`G` across the `G` parallel links (`init_network()`:
`link_bw = inter_bw_mbps / G`). This is the detail that makes the method a
*routing* answer rather than a bandwidth answer: the aggregate P<->Q
capacity is identical to the single-gateway case, so any improvement comes
from spreading fan-in across paths, not from provisioning more bytes/s.

**What "multi-gateway" does *not* mean**: a single (src, dst) pair's traffic
does not split across the `G` links — it hashes to exactly one, deterministically.
What spreads across all `G` links is a GPU's *aggregate* traffic: in one
all-to-all round a GPU talks to every other GPU in the neighboring panel,
and each of those destinations can hash to a different gateway.

## 5. Tunables (implemented, `glassfb_topology.h`)

- `GLASS_GW_PARALLEL` (int, default 1): `G` above. Clamped to the panel's
  actual edge-pool size for the active `GLASS_INTER` mode (4 for `mesh`;
  `panel_size / panel_degree()` for the older `fb2`/dragonfly modes, which
  don't model discrete edges).
- `GLASS_INTER=mesh`: selects the 4-edge mesh topology described above
  (alternatives: default dragonfly, `fb2`).
- `GLASS_ECN_K`: unrelated but adjacent finding — more aggressive ECN
  marking partially mitigates the same incast (tested independently; see
  session history), but is a tuning knob, not a structural fix. Multi-gateway
  routing is the structural fix; the two are not mutually exclusive.

## 6. Validated results (see `experiments/results/serving_sweep.csv`)

At fixed total inter-panel bandwidth, `G=1 -> G=4` on real LLMServingSim
routing/profiling data (EP=32, 2 panels; EP=64, 4 panels in a 2x2 mesh grid;
4 workload types x {400,800,1600 GB/s}):

- EP=32, agentic-prefill, 800GB/s: 106ms -> 44ms (the original pathological
  point), with the RTO count dropping in step.
- The fix generalizes across all 4 workload types and both EP=32/64, not
  just the one anomaly that surfaced it.

## 7. Status at full (512 GPU) scale

By construction, `G<=4` under `mesh` is **scale-independent** — each edge is
always exactly 4 GPUs (one row/column of a fixed 4x4 intra-panel grid),
regardless of how many panels exist overall. This differs from the earlier
(incorrect) `fb2`-topology finding that `G` collapsed to 1 at 512 GPU: that
collapse was an artifact of `fb2`'s degree-10 connectivity (every panel
directly linked to all 10 panels sharing its grid row or column), which has
no physical realization and was replaced by `mesh` for exactly this reason.
Under `mesh`, G=4 is expected to remain available at 512 GPU the same way it
was validated at 64 GPU (Section 6) — **this has not yet been run** at the
full 512-GPU scale (that run is slow, hours per point, and is queued behind
regenerating the fat-tree/full-bisection baselines under the corrected
methodology in `experiments/README.md`). Confirming G=4's benefit holds at
512 GPU, not just assuming it from the per-edge invariant, is the next step
before this method is fully validated end to end.
