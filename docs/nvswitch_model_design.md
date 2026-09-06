# Packet-level NVL72 / HGX model for htsim — design (2026-09-06)

Decision (user): the panel stays 4×4; the NVLink baselines move from the analytic,
contention-free island to a **packet-level single-stage NVSwitch Clos**, so that both
fabrics are simulated with queues, and the comparison at EP ≤ 64 is symmetric (glass pays
gateway incast; NVLink pays switch-port contention). The hierarchical A2A work follows
this, not the other way round.

## 1. What is being modelled

| | HGX-8 (H100, NVLink4) | NVL72 (GB200, NVLink5) |
|---|---|---|
| GPUs per domain `D` | 8 | 72 physical; **64 used** (MixNet §8 convention; compute-matched) |
| switch chips `S` | 4 (NVSwitch3) | 18 (9 trays × 2) |
| links per GPU | 18 × 25 GB/s/dir, spread 5/5/4/4 over 4 chips | 18 × 50 GB/s/dir, one per chip |
| model link rate `L` per (GPU, switch) | 112.5 GB/s (=4.5 × 25) | 50 GB/s |
| per-GPU injection = `S·L` | 450 GB/s/dir | 900 GB/s/dir |
| hop latency | 250 ns per hop, 2 hops (GPU→switch→GPU) | same |
| scale-out NIC | 400G = 50 GB/s/dir | 800G = 100 GB/s/dir |

Per-direction rates follow the paper's quoting convention (NVLink halved from the
bidirectional headline, Ethernet per direction as marketed). The 72-vs-64 choice is a flag.

## 2. Topology class `NVSwitchTopology` (new file, next to `flat_topology.cpp`)

Clone the structure of `FlatTopology` (queues[j][k]/pipes[j][k], `alloc_queue`, the
`FLAT_PORT_CAP` feeder and its banner) and add a switch tier.

Node ids: GPUs `0..N-1`, domain `d = g / D`. Switch `s` of domain `d` has id
`N + d·S + s`. Per domain, for every GPU `g` and switch `s`:

- `up[g][s]`   : Queue + Pipe, GPU→switch, rate `L`, latency `nvs_lat`
- `down[s][g]` : Queue + Pipe, switch→GPU, rate `L`, latency `nvs_lat`

So each GPU has `S` egress queues (egress cap = `S·L`, no extra feeder needed inside the
domain) **and** each GPU has `S` ingress queues on the switch side (ingress cap = `S·L`).
This is strictly better than the flat feeder (which was egress-only): incast inside an
NVSwitch domain is now capped the way a real switch port caps it.

Cross-domain: reuse `FlatTopology`'s all-pairs link at the NIC rate with the port-cap
feeder (`FLAT_PORT_CAP`), latency `-rtt 2000`, exactly as the island baselines run today.

`get_paths(a, b)`:
- same domain, `a≠b`: return **S routes**, route `s` = `[up[a][s], pipe, down[s][b], pipe, sink]`.
  `ffapp` already picks `rand() % size()` (ffapp.cpp:1280) → per-flow ECMP across the S
  switches with no ffapp change.
- different domain: return the one NIC route `[feeder[a], queue[a][b], pipe, sink]`.
- reverse path symmetric (`get_paths(b, a)`), as in flat.

`get_neighbours`, `no_of_nodes` as in flat. Ignore `conn`/`expert2gpu` (unused).

## 3. Striping — three modes, in order of fidelity

NVLink stripes one transfer across all 18 links; a TCP flow in htsim follows one route.

1. **ECMP per flow (default, zero code)** — each flow ≤ `L`. Correct for A2A (63 flows per
   GPU fill all switches), pessimistic for single large flows (a DP all-reduce or PP step
   between two GPUs gets 50 GB/s instead of 900). Report this limitation on every row
   (`stripe=ecmp`).
2. **Per-packet spray (`-DPACKET_SCATTER`)** — `tcp.cpp:640–652` already round-robins
   packets over `_paths` when compiled with `PACKET_SCATTER` (tcp.h:41 is commented out),
   and every `ffapp` start_flow site already calls `set_paths()` under the same ifdef. A
   separate binary `htsim_tcp_nvswitch_scatter` built with that define models NVLink's
   link striping directly. **Blocker to check first:** how `tcp.cpp:906/1005` treat
   reordering — if per-packet spraying triggers dup-ACK fast retransmit storms, mode 2 is
   unusable and mode 3 is the fallback. Verify on the G1 microbenchmark below before
   any paper row uses it.
3. **Subflow striping in ffapp** — split each transfer into `S` TcpSrc of `size/S`, subflow
   `k` pinned to route `k` (`srcpaths->at(k)`), completion = last subflow. One helper
   called from the five `start_flow` sites (ffapp.cpp:1279, 1568, 1836, 1947, 2080, 2214,
   2427, 2580 — the same `choice = rand()` block each time), ~60 lines. Flag `-nvs_stripe S`
   (default 1 = mode 1). Only if mode 2 fails.

## 4. Transport (derived, printed)

- NVLink tier BDP: `L × 2·nvs_lat` = 50 GB/s × 500 ns = 25 KB ≈ 17 pkts at 1500 B. Use
  `q = k·BDP` with `k` printed; start at k=8 (`-nvs_q 136`), sensitivity k∈{4,8,16} on the
  EP=32 row. ECN K as a fraction of `q`. Real NVSwitch ports buffer far more than 8×BDP,
  so k=8 is conservative for NVLink.
- NIC tier: as the island baselines (q ≈ 4×BDP at 2 µs, printed `q_over_bdp`).
- RTO floor 100 µs (every row in the paper), MTU 1500.

## 5. Flags and banner (`main_tcp_nvswitch.cpp`, cloned from `main_tcp_flat.cpp`)

`-nvs_domain D` (64) · `-nvs_switches S` (18) · `-nvs_link GBps` (50, decimal) ·
`-nvs_lat ns` (250) · `-nvs_q pkts` · `-nvs_ecn_k pkts` · `-nvs_stripe {ecmp|scatter|N}` ·
`-speed` (NIC, Mbps) · `-port-cap` · `-port-cap-pkts` · `-rtt` (NIC hop) · `-island_gpus 1`
(the analytic shortcut must be **OFF**: the domain is now simulated; print that it is off).

Banner (one line each, so a row states its substrate):
```
NVSwitch model: D=64 GPUs/domain, S=18 switches x 50 GB/s (= 900 GB/s/GPU/dir), hop 250 ns
NVSwitch queue: 136 pkt (8.0x BDP at 500 ns RTT), ECN K 68, stripe=ecmp, analytic island OFF
Scale-out: 100 GB/s NIC per GPU, feeder 540 pkt (4.0x BDP at 2000 ns), EGRESS ONLY
```

## 6. Gates (before any paper row)

- **G1 single-transfer microbenchmark**: 2 GPUs in one domain, one 1 GB transfer.
  Expected: mode 1 ≈ 50 GB/s (one link); mode 2/3 ≈ 900 GB/s × TCP efficiency. Record
  both numbers in the commit; they anchor the striping statement in the paper.
- **G2 A2A saturation**: 64 GPUs, one domain, uniform A2A of 64 MB per pair. Aggregate
  throughput should approach `64 × 900 GB/s` in all modes (A2A has enough flows). Report
  achieved fraction and RTO count (expect 0 at k=8).
- **G3 determinism**: fixed seed, two runs, identical makespan (the `410025604`-style gate).
- **G4 reduction to the island**: with `-nvs_link 900 -nvs_switches 1 -nvs_lat 0 -nvs_q huge`
  the EP=16 LLaMA-MoE row must come out within a few % of the analytic island's 86.508 ms
  (not bit-exact: queues vs analytic), which shows the class is wired correctly.

## 7. Runs once gated (paper_ref=cliff, system=nvl64_pkt / hgx8_pkt)

LLaMA-MoE EP 16/32 and qwenMoE top-4 EP 64, mb8, derived transport, stripe mode 1 and
(if usable) mode 2; then Arctic EP=128 (paper_ref=beyond) with the NIC tier. Keep the
analytic-island rows as the "contention-free upper bound" line in the figure.

## 8. Size estimate

`nvswitch_topology.{h,cpp}` ≈ 350 lines (mostly flat_topology with a switch tier);
`main_tcp_nvswitch.cpp` ≈ flat main + 8 flags + banner; Makefile target (+ scatter
variant); no ffapp change for mode 1/2, ~60 lines for mode 3. Gates G1–G4 are four
short runs. Estimated one working day including gates.

## 9. Paper text this enables (§method)

"NVLink domains are simulated packet-level as a single-stage Clos of S switch chips with
one L GB/s link per (GPU, chip), each port a queued pipe (D×S ports per domain), with
per-flow ECMP [or per-packet striping] across chips and transport derived for that tier;
the earlier contention-free island is retained only as an upper bound."
