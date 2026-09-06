# Hierarchical (gateway-aggregated) all-to-all for Glass-FB — design (2026-09-06)

Order (user): build AFTER the packet-level NVSwitch model (docs/nvswitch_model_design.md)
is gated. This document exists so the build can start the same day.

## 1. Why

Every EP>16 glass row loses to its **tail**, not its throughput: at EP=64 the 3200 edge
improves mean FCT 18% and P99 38% while the max FCT goes 91 → 565 ms (edge_ep64), and the
only rows that ever time out are glass rows crossing a panel edge (paper_todo A8). The
mechanism is gateway incast: with `FFAlltoAll::doNextEvent()` (ffapp.cpp:2301) every
(src, dst) pair of the EP group starts its own DCTCP flow at once, so a panel pair
(p, q) carries 16 × 16 = 256 concurrent flows through G=4 gateway links, 64 per link, each
with its own slow-start and its own chance of an RTO. The A2A volume per panel pair is
fixed; only the flow structure is ours to choose.

## 2. What changes

A two/three-stage A2A that keeps the same bytes but crosses each edge with **G flows per
panel pair** instead of 256 (DeepEP's intra-node → inter-node split; NCCL PXN), so the
edge sees a few long flows in congestion avoidance instead of 64 short flows in incast.

For an A2A task over an EP group spanning panels `P = {p₀ … p_{k−1}}` (panel(·) from
`GlassFBTopology`):

- **intra-panel pairs** (`same_panel(s, d)`): unchanged, direct flow of `operator_sizes[s][d]`.
- **cross-panel pairs** (`panel(s)=p ≠ q=panel(d)`), for each ordered panel pair (p, q):
  - choose the `G` gateway GPUs of p on the edge facing q (`edge_local(dir, g)`, the same
    slots the multi-gateway routing already uses), `gw_p[g]`, g = 0..G−1, and likewise
    `gw_q[g]` on q's edge facing p.
  - **stage 1 (gather, intra-panel):** every `s ∈ p` sends to `gw_p[g(s)]` the concatenation
    of its payloads to all `d ∈ q`: size `Σ_{d∈q} operator_sizes[s][d]`. `g(s) = s mod G`
    spreads the 16 senders over the 4 proxies (4 senders per proxy). Skip if `s` is itself
    `gw_p[g(s)]`.
  - **stage 2 (edge, one flow per gateway):** `gw_p[g] → gw_q[g]`, size = Σ of what it
    gathered. G flows per (p, q), each over its own gateway link → **no incast**: one flow
    per link, sized at ~1/G of the panel-pair volume.
  - **stage 3 (scatter, intra-panel):** `gw_q[g] → d` for every `d ∈ q`, size
    `Σ_{s: g(s)=g} operator_sizes[s][d]`. Skip self.
- Dependencies: stage 2 of (p, q, g) starts when its 4 stage-1 flows finish; stage 3 of
  (q, g) starts when stage 2 of (p, q, g) finishes. Task completes when every stage-3 flow
  (and every intra-panel direct flow) has finished. `total_rounds` counts all flows of all
  stages; `finish_alltoall` gains a per-(p,q,g) countdown that launches the next stage.

Bytes moved: identical across the edge; +2× the cross-panel bytes on intra-panel links
(gather + scatter). That intra cost is what the width sweep says is free (400 → 896 GB/s
changed nothing), and it is the experiment's honest price to report.

## 3. Implementation (ffapp only; topology untouched)

- `FFApplication` flag `a2a_hier` (default false) set by `-a2a_hier` in
  `main_tcp_glassfb.cpp`; banner prints `A2A: hierarchical, G=4 proxies per panel pair`
  or `A2A: flat (all pairs direct)`.
- `FFAlltoAll::doNextEvent()`: if `a2a_hier` and `dynamic_cast<GlassFBTopology*>(ffapp->topology)`
  succeeds, build the stage plan (a small struct per (p, q, g): stage-1 list, stage-2 pair,
  stage-3 list, sizes, countdowns) and start intra-panel direct flows + all stage-1 flows.
  Otherwise the existing loop.
- `FFAlltoAllFlow` gains `stage` and a pointer to its (p, q, g) plan entry;
  `finish_alltoall()` decrements the entry's countdown and calls `start_flow` for the next
  stage when it hits zero. `start_flow(src, dst, size)` overload taking an explicit size
  (today it reads `operator_sizes`).
- Intra-node shortcut stays as it is (glass runs with it OFF).
- ~150 lines. No change to routing, transport, or the topology class; `get_paths` already
  routes gateway→gateway over the right edge because the multi-gateway hash keys on local
  panel positions (the proxy slots ARE the gateway slots).

## 4. Gates

- **G1 byte conservation:** per-edge bytes in the hierarchical run equal the flat run's
  (from `fct_util_out`), and intra-panel bytes rise by exactly 2× the cross-panel volume.
- **G2 EP=16 unchanged:** with the whole EP group in one panel there are no cross-panel
  pairs → makespan bit-identical to the flat A2A (the switch is inert there).
- **G3 EP=32 LLaMA-MoE @1600 mb8:** flat 186.383 ms / 368 RTO vs hierarchical; report
  makespan, RTO, mean/P99/max FCT. Expected: RTO → 0, max FCT collapses, makespan improves
  by the incast share of the EP=32 gap (decomp says 48.7% of bytes cross the edge).
- **G4 EP=64 qwenMoE top-4 @1600 and @3200:** the 3200 "reversal" row. If the tail was
  incast, hierarchical @3200 should now beat @1600.

## 5. Paper text this enables

"Because the switchless gateway is an incast point, we aggregate cross-panel traffic at
the gateway GPUs: a three-stage all-to-all (intra-panel gather, one flow per gateway link,
intra-panel scatter) that moves the same bytes across the edge with G flows per panel pair
instead of 256. It costs 2× the cross-panel bytes on intra-panel links, which the width
sweep shows are not the bottleneck, and removes the retransmission tail that set every
EP>16 makespan." — rows `system=glassfb_hier` alongside `glassfb` in cliff/edge_ep64.
