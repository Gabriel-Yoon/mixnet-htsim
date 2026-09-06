# Paper TODO — single source of truth

Reconciled between the two working sessions. Numbering follows the peer session's
consolidated list; items E35+ are additions from this session's simulation log.
`main.tex` edits are PAUSED (D33) — this file is where decisions live until they resume.

Status legend: **[SETTLED]** decided, **[BLOCKED]** waiting on a run, **[OPEN]** needs a decision.

---

## A. Sentences that must appear

- **A1 [SETTLED — reworded, "upper bound" was wrong]** Transport scope caveat, citing WaveCC [wavecc]: *"Our transport is a datacenter TCP/DCTCP stack over lossy queues, inherited from MixNet. On-package fabrics are credit-flow-controlled and lossless [wavecc]; their failure mode under the same burst is backpressure stall rather than loss and timeout, so our absolute congestion costs are not transferable. The incast at the inter-panel gateway is the structural feature common to both."*
  The earlier "upper bound on a lossless transport" phrasing is **retracted**: a lossless fabric does not lose *less*, it fails *differently*. WaveCC §2.2/§3.1.1 gives this on the record — WSC fabrics are lossless with credit backpressure, buffering is tightly bounded and cannot be over-provisioned for headroom, and RTT-based signals are too slow when a hop is nanoseconds (their Fig 10: TIMELY/DCQCN feedback loops run hundreds–thousands of cycles, longer than a whole communication phase). Cite it rather than asserting it.
- **A35 [NEW]** Simulator-limitation sentence. WaveCC chose BookSim2 because discrete-event and ML/HPC simulators "do not natively capture cycle-level backpressure" — a critique that applies to htsim verbatim. State in methodology: htsim models packets and TCP, not cycle-level credit backpressure; consequences per A1.
- **A36 [NEW]** Report **P99 FCT alongside makespan**, and stall fraction on any lossless run. Makespan is a max over flows and so tail-dominated; WaveCC's Fig 3 shows 1% tail inflation costing 14–22% of throughput. htsim already logs per-flow FCT, so the P99 column is free — I'll add it to the result scripts.
- **A2 [SETTLED]** Configuration-provenance paragraph — `docs/methods_provenance.md`, approved as written. Count confirmed at **six**: weight-matrix wrap, 9000/1500 packet size, WG uni/bi, `GLASS_OPT_BW` unset, intra-node shortcut, `-q` vs MTU. The ECN_K/cwnd-in-packets finding (E35) is a sub-note of #6, not a seventh.
- **A3 [BLOCKED on corner]** Transport derivation on the page, each system at its own derived point, both derivations side by side, plus a cross-check each way.
- **A4 [SETTLED]** Baseline substrate: electrical baselines keep the 8-GPU NVSwitch island (MixNet §7.1); the glass panel has none. Shortcut ENABLED for the former, DISABLED for the latter (`6d3fae7`/`e2fc399`).
- **A5 [SETTLED]** Compute-matched comparison stated explicitly, WATOS style.
- **A6 [SETTLED]** Quoting-convention footnote (`docs/interconnect_parameters.md` §4b).
- **A7 [SETTLED]** Line 570 "does not beat full bisection on topology" stays; wins are on bandwidth, iso-bandwidth loss disclosed alongside.
- **A8 [SETTLED]** The switchless trade-off sentence, presented together with B23.

## B. Claims to restate or remove

- **B9** ~line 659 "1600 GB/s ≈ 13 waveguides" → **25**. "~19 of 60" as panel average is correct, keep.
- **B10 [BLOCKED]** Re-decompose the 85 ms breakdown at derived transport. Note: the decomposition tool itself is affected — see **E39**.
- **B11 [BLOCKED]** §dse "knees at 150–300 GB/s" contradicted; re-run at derived transport. **E36 suggests the replacement claim is much weaker than either version.**
- **B12** Limitation (2) resolved via mesh G=4 + inter provisioning; attribute to inter, not intra; pair with A7.
- **B13a [NEW]** WaveCC Fig 5 / §2.4.2 is a **citable precedent for our bottleneck-displacement signature**: increasing stride first reduces cycles/timestep, then *increases* it while the stall rate keeps falling — "the bottleneck shifts from congestion to self-throttling". Same shape as our "RTO up, makespan down" and "more bandwidth is worse" results, observed in a cycle-accurate lossless model. This is evidence that what we measured is a known property of bursty phased traffic on bounded-buffer fabrics, not a simulator artifact. Use it wherever E36's non-monotonicity is reported.
- **B13** "fixable by provisioning alone" → "by inter-panel provisioning **or** buffering, at a stated transport configuration" (q 10000→12000 at inter 2000 gives 0 RTO).
- **B14 [BLOCKED]** "Beyond one panel" 222→41.7 ms, 2.7×, Lightmatter coincidence — unreadable until re-run; the coincidence sentence likely dies.
- **B15 [BLOCKED, see E36]** Pareto 7.1× → ~1.6× at 1 ms; the "2400 required → 200G/lane" feasibility argument does not survive. Keep both MTP-16 candidates.
- **B16** Abstract 1.4–1.9× vs fat-tree is no longer the headline; do not substitute an NVLink number without packet-level runs at derived transport.
- **B17** EP=16 vs dom64 win narrows to "we remove the switch hop", stated with the matched-latency numbers (500/500 → 1.3% tie; 100/100 → they win 4.1%).
- **B18** No pure-performance win vs NVL72/dom64 at any EP. Report plainly; case is GB/s/W + tiling beyond 64/72.
- **B19 [BLOCKED]** nvl4_dom8 450→900 conclusion VOID; re-run now that `GLASS_ELEC_BW` is actually read.
- **B20** EP=8 row: zero TcpSrc, no network simulation. Drop or label explicitly.
- **B21** RDL 1800 GB/s is **free electrical overprovisioning, not a performance contributor** (elec ×2 picosecond-identical, ÷2 = +0.02%). Say so; do not claim it as a win. *(This answers the user's direct question: 1800 is not wrong, it is simply not doing work at these operating points — an honest "we had headroom and used it" rather than a tuned parameter.)*
- **B22** Energy/token is invariant to provisioning (state as robustness). "Wide improves energy 3.1→5.8×" RETRACTED. `provisioned` mode is one-sided sensitivity only. Re-provisioning's benefit is GB/s/W.
- **B23** Iso-power win count will rise after the floor fix; legitimate, but must appear with A8.
- **B24 [RESOLVED — see E38]** No longer suspended.
- **B25** Relabel serving_sweep_wide as "intra width as relay resource at EP=64"; keep.

## C. Structure decisions

**C32 additions (from WaveCC's references, neither currently cited in main.tex):**
Chen, Pal & Kumar, "Waferscale network switches", ISCA'24 — the *switched* counterpart to our switchless claim, so a direct comparison point. Miyajima & Fukuoka, "Benchmarking the Cerebras WSE-2", SC'25 workshops — a source for real network-on-wafer credit and latency numbers.

**C33 [NEW] Reframe multi-gateway as injection shaping, not bandwidth.** WaveCC §2.2's on-chip answer to congestion is injection control, not headroom. Our G=4 gateway spreading changes *where and when* bursts enter the inter-panel link, so it is an injection-shaping mechanism; one sentence framing it that way is stronger than framing it as bandwidth, and it is consistent with E36 (where bandwidth buys under 7%).

**C34 [NEW] Vocabulary bridge.** Our two-phase dimension-ordered FB all-to-all is a stride-2 wavelet in WaveCC's terms — only one dimension injects per phase. One background sentence. Related work: WaveCC is the precedent for closing a congestion loop from a local hardware signal on a wafer fabric, and credit-guided injection at our gateway GPUs is the natural future work (their Appendix D conditions — fixed pattern, phased injection — hold for EP-placed MoE all-to-all).

**Do not over-lift:** MD traffic is nearest-neighbour small-message, ours is all-to-all with large prefill messages, so transfer *no* numbers. Their PEs sit behind routers; our panel is switchless direct links, so a credit signal would live at the EIC/PIC link layer, not a router. State the analogy, not equivalence.

C26–C32 as listed by the peer session, all **[SETTLED]**: baseline set and two normalizations (C26); FRED-style Glass-A→D ladder (C27); FRED-Fig-10 decomposition (C28, but see E39); multi-gateway as a packaging requirement (C29); MTP-16 quantum (C30); WG budget by optical degree (C31); positioning vs Mozart / MixNet / Lightmatter / switchless-dragonfly (C32).

## D. Standing constraints

D33 (main.tex paused), D34 (two-commit rule; banner-or-inadmissible) — **[SETTLED]**.

---

## E. Additions from this session

- **E35 [SETTLED — corrects the record]** The iso-byte MTU result and its **mechanism**. At a byte buffer held at ~14.3 MB, mtu 9000 is *worse*, not better: inter 2400 goes 6.449 ms / 0 RTO → 24.151 ms / 1345 RTO, a 3.7× regression. The mechanism is **not** "fewer packet slots" (an earlier claim of mine, retracted): drops are byte-denominated (`queue.cpp:57`, `_queuesize + pkt.size() > _maxsize`). What *is* packet-denominated, and so 6× larger in bytes at mtu 9000, is the ECN marking threshold (`glassfb_topology.cpp:173`, `memFromPkt(_ecn_k_pkts)` → 450 KB vs 75 KB) and the initial congestion window (`tcp.cpp:182`, `_cwnd = 100 * _mss` → 900 KB vs 150 KB per flow, across ~1024 simultaneous flows). Jumbo frames lose because the incast burst is 6× bigger and marking fires 6× later into the same byte buffer. **Action: ECN_K should be byte-denominated or a fraction of the byte buffer** — this is a design lever, not only a note.
- **E36 [BLOCKED on 12872572, but the signal is already strong]** At the physically-derived corner, inter-panel provisioning barely matters. Partial results (EP=64 coding_prefill, intra 384, shortcut OFF, mtu 1500):

  | q | floor | inter 1600 | 2000 | 2400 | 3200 |
  |---|---|---|---|---|---|
  | 1000 | 100 µs | 13.052 (3776) | 13.052 (3776) | 13.816 (2217) | 13.816 (2217) |
  | 1000 | 1 ms | 14.747 (3776) | 14.747 (3776) | 13.174 (2217) | 13.174 (2217) |
  | 2000 | 100 µs | 14.147 (2828) | 14.147 (2828) | 13.214 (1292) | 13.214 (1292) |

  Two observations that bear directly on B11/B14/B15. (i) The whole 1600→3200 range spans **under 7%**, and the direction is **not monotonic** — at q=1000/100 µs more bandwidth is *slower*. (ii) 1600 and 2000 are bit-identical, as are 2400 and 3200, so the response is a two-level step, not a curve. If this holds across the remaining cells, the provisioning claim as written does not survive at derived transport in any form: **1600 GB/s (one MTP-16 at 100G/lane) suffices**, and the 200G/lane feasibility argument becomes unnecessary rather than merely unsupported. That is a *better* result for the paper's feasibility story than the one it replaces.
- **E37 [OPEN — cheap, but worth LESS than I first pitched it]** A lossless-queue run does **not** produce "the lossless bound", because per A35 htsim cannot model cycle-level credit backpressure either; it would model lossless queues with a TCP stack on top, which is neither our lossy model nor a real credit fabric. What it *does* buy is a decomposition: it separates how much of our congestion cost is **loss and timeout** from how much is **queueing delay**, which is worth having and is honest if labelled that way. It does not require patching `ffapp`'s transport. `main_tcp_glassfb.cpp:354` hardcodes `ECN` as the topology's queue type, and `GlassFBTopology::alloc_queue` already implements `LOSSLESS`, `LOSSLESS_INPUT` and `LOSSLESS_INPUT_ECN`. `LOSSLESS_INPUT_ECN` (lossless with ECN marking) is the right model for a credit-based fabric with congestion notification — i.e. what NVLink/UCIe/our glass links actually are. This is a flag, not a patch. Caveats: the lossless paths hardcode their own buffer sizes (`memFromPkt(50)`, `(200)`, `(10000)`), `LOSSLESS` additionally constructs `Switch` objects in `init_network`, and DCTCP over a queue that never marks would never back off — so `LOSSLESS_INPUT_ECN` specifically, and it needs a smoke test before it is trusted. **Recommend doing it, relabelled**: report it as "congestion cost with loss removed", never as a lossless-fabric bound.
- **E38 [RESOLVED — closes B24]** ARM A's width degeneracy is **real, not a shortcut artifact**. At mb=16 with the shortcut DISABLED: opt 400 → 187.403 ms, 512 → 185.237, 640 → 185.237 (896 pending). The old shortcut-ON row was 400 → 186.613, 512/640/896 → 185.652. So widening the intra optical tier past ~512 GB/s changes nothing either way, all rows at 0 RTO. The correct statement is **"intra-panel optical width saturates above ~512 GB/s at EP=16"**, which supports C31's 640 budget choice as sufficient rather than as a compromise. It does *not* license the stronger "intra is never the bottleneck" — that was only ever tested at EP=16 with inter pinned at 200.
- **E39 [OPEN]** `scripts/decompose_flows.py` reads `flow_size:` lines that are emitted *before* the shortcut test, so on any pre-`e2fc399` log it counts flows that never touched a wire and overstates the intra share by up to 2× (50% of flows eligible at EP=16, 12.5% at EP=64). A warning is committed on the script. **C28's FRED-Fig-10 decomposition must be regenerated from post-`e2fc399` logs** — the existing decomposition cannot be used.
- **E40 [SETTLED]** Every result CSV must carry a **byte** buffer column, not just `-q`. Because `-q` is in packets, two rows with the same `-q` and different MTU had different buffers, which is what produced instance #6. Applied going forward in `buffer_vs_mtu.csv` and `derived_corner.csv`.
- **E41 [SETTLED]** The buffer knee at the Ethernet default corner is sharp and then flat: at inter 2000, q=10000 → 46.028 ms / 68 RTO, q=12000 → 7.281 ms / 0 RTO, and q = 14000/16000/18000/20000/40000 all → 7.394 ms / 0 RTO. So the timeout regime ends between q=10000 and 12000 and nothing is gained above it. Useful for B13's "or buffering" clause and as evidence the 14.4 MB default sat just below a knee — a coincidence worth stating, since it is why the default looked catastrophic.

---

## Open questions for the user

1. **E37** — spend one smoke test on `LOSSLESS_INPUT_ECN` to turn the scope caveat into a measured bound? Recommended.
2. **E36** — if the corner confirms, the feasibility argument *improves* (100G/lane parts suffice) while the provisioning narrative weakens. Confirm that trade is acceptable before either is written.
