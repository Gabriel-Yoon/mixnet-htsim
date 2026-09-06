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
   link striping directly. **Checked (peer, 2026-09-06):** reordering is tolerated by
   construction — `set_paths()` raises `DUPACK_TH = 3 + paths` (tcp.cpp:136) and the
   fast-retransmit test uses it (454–457), so S=18 gives a threshold of 21, which covers
   round-robin reordering over equal-latency paths. Two caveats: (a) the `PACKET_SCATTER`
   destructor block (tcp.cpp:112–120) has bit-rotted and **does not compile** (range-for
   over a raw pointer, const dropped) — a two-line fix, so this is not "flip -D and
   rebuild"; (b) the threshold covers path multiplicity, not differential queueing: under
   heavy incast one chip's egress queue can run far deeper than another's and a packet can
   fall behind by more than 18, firing spurious fast retransmits — exactly the A2A case
   this model studies, so G2's RTO/retransmit count also tests this, and `DUPACK_TH` goes
   in the banner. Decision: build mode 1 first; mode 2 is a follow-up gated on G1/G2
   showing single-flow bandwidth is binding.
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

## 10. Real costs of the incumbent the model must charge (user, 2026-09-06)

Rule: every item below is a documented property of shipping NVLink/NVSwitch systems that
the analytic-island model gave away for free. Each needs a citable number before it is
switched on; none is a tuning knob. Flags default to the *charged* value once sourced,
with the uncharged value available for the sensitivity row, and the banner prints all.

| # | cost | how it enters the model | flag | source needed |
|---|---|---|---|---|
| 1 | NVLink achievable vs nominal bandwidth (flit/CRC/protocol overhead; NCCL busbw reaches a fraction of peak) | `L_eff = L × η_nvl`, η from a microbenchmark (nvbandwidth / NCCL all-to-all busbw on H100 and GB200) | `-nvs_eff` | Hopper/Blackwell dissection papers (Luo et al. 2024-25), nvbandwidth results |
| 2 | GPU→NVSwitch→GPU latency as measured, not the raw link figure | `nvs_lat` per hop from a measured P2P latency through NVSwitch, split evenly over 2 hops | `-nvs_lat` | same microbenchmarks (H100 NVSwitch P2P ≈ 1–2 µs at NCCL level, ≈0.7 µs hardware) |
| 3 | HGX-8's unequal link distribution over 4 NVSwitch3 chips (5/5/4/4) | per-chip link rate 5×25 / 5×25 / 4×25 / 4×25 GB/s instead of a uniform 112.5; ECMP then lands 25% of flows on the thin chips | `-nvs_links_per_chip 5,5,4,4` | NVIDIA HGX H100 NVSwitch topology (public system docs) |
| 4 | Scale-out beyond the domain is a multi-tier IB/Ethernet fat-tree, not an ideal non-blocking pipe | replace the all-pairs flat NIC path with a 2-tier (rail-optimized) fat-tree at a documented oversubscription (1:1 rail, 2:1 spine typical), end-to-end latency 3–5 µs including PCIe/NIC traversal at both ends | `-scaleout fattree -so_oversub 2 -so_lat 4000` | RDMA/IB microbenchmarks; DGX SuperPOD reference architecture (rail-optimized, oversubscription stated) |
| 5 | NIC-side PCIe path: GPUDirect RDMA through PCIe Gen5 x16 (64 GB/s) | cap the NIC path at min(NIC, PCIe) per GPU; binds for 800G NICs on Gen5 hosts, not for Gen6 (GB200: state which) | `-so_pcie 64` | PCIe spec + platform docs |
| 6 | 8 of 72 GPUs stranded when EP groups are powers of two (64 used) | count the 8 idle GPUs' cost in iso-power / iso-cost rows (11% of rack compute and its static power) — a table row, not a simulation change | — | NVL72 = 72 GPUs (public) |
| 7 | Power for the cross-domain path: NIC + scale-out switch port share, not NIC alone | `whole_power2.py`: add per-GPU share of the 800G switch tier (W/port from a switch datasheet) to the NVL-64 beyond-64 rows; glass edges have no switch tier | — | switch ASIC/system datasheet (the dragonfly ref already cites 1.7 kW per 64×400G) |
| 8 | NVSwitch tray power and NVLink SerDes energy at the sourced 1.55–5 pJ/bit bracket (already in) | unchanged | — | done |
| 9 | Copper reach: NVL72's spine is copper within one rack; every domain beyond it is optical anyway | qualitative sentence in §method, no model change | — | GB200 NVL72 system description |

What is **not** charged, and why: NCCL/software launch overheads (apply to both fabrics),
TCP-vs-credit-flow (already disclosed as a symmetric limitation), and anything without a
number we can cite. Order of switching on: 1, 2, 3 (inside the domain, cheap, all
microbenchmark-sourced) → 4, 5 (scale-out, only affects EP>64 rows) → 6, 7 (accounting).
Every charged row carries the uncharged value as a sensitivity row so the effect of each
cost is visible on its own.
