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
- **B26 [NEW — a claim with no data behind it]** Fig 7c (fig_copperfb) and its §winbw sentence — "the same FB topology in copper runs 1.8× slower than glass and 28% behind a fat-tree at 100 GB/s" — have **no script and no data row in any repo**. Grep over every committed figure CSV finds 100 GB/s rows only for fattree / flat / fc, never for an FB topology, and "copper" appears nowhere. Regenerate: copper-FB is just the glass topology with the optical tier at 100 GB/s, so the three bars are `GLASS_OPT_BW=100` vs `384` (or `640`) vs `fattree@100`, on LLaMA-MoE EP=16 mb8 under corrected methodology.
  **Caveat on reusing ARM A for the glass side:** ARM A ran at `GLASS_INTER=fb2`, inter 200, G=1, q=10000, default RTO floor — the *pre-correction* transport. It is not comparable with a new fat-tree@100 row taken at derived transport, so the glass bars must be re-run too. Three fresh runs, not one.
  This matters more than a figure regen usually would: it sits next to the abstract's claim that **glass, not the FB topology, is the win**.
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

- **E42 [OPEN — the paper claims a knob it never turns]** The synthetic-traffic disclosure **already exists** (main.tex 462 "the per-expert skew is a synthetic Zipf weight-matrix … its exponent a sensitivity knob", restated in limitation (1) at 653). What does not exist is the sensitivity it asserts — no skew sweep appears in any results CSV. Run skew ∈ {1.2, 1.6, 2.0} on one config per regime (coding_prefill EP=64 and qwenMoE EP=64, at the derived corner) and cite it from 462. Record also that `gen_weightmatrix.py` reads only `ep`, `--skew` (default 1.6) and `--seed` (0) — not the model, checkpoint, or top-k — so **any two models at the same EP share the pairwise traffic distribution exactly**. Consequence: the two EP=64 architectures are a *controlled* comparison (architecture effect at fixed traffic), not an independent robustness check; the skew sweep is what covers the traffic axis.
- **E44 [SETTLED — checked, immaterial]** The single global `-q` cannot be 2–4× BDP for both tiers at once (intra BDP 256 pkts, inter 1200). Measured both ratios across the corner: q=1000 is 3.9× intra / 0.8× inter, q=5000 is 19.5× / 4.2×. Makespan across that whole range is 11.69–15.05 ms, so the tiers do split and **the result does not depend on the compromise**. Per-tier queue knob therefore **not built** — a limitation that was checked and found not to bind, rather than an untested caveat.
- **E45 [SETTLED — process]** Provenance tooling needs the same idempotence discipline as runs. `classify_measure_mode.py` originally rewrote each `.meta` from scratch, so re-running it silently erased curated exclusions and `mode_source` fields, and the re-run looked authoritative while being less informed than the run before it. Now merges (measured fields recompute, curated fields survive) and verified idempotent across two consecutive runs. Same failure shape as the six instances — plausible, self-consistent, wrong, no error — with the record as the victim. Belongs in §4b beside E43.
- **E46 [PIPELINE COMMITTED; PROVENANCE STILL UNRECORDED]** The figure pipeline is now in the repo (`55d4b9c`, `307f4d0`: `FIGURES.md`, `scripts/figures/`, `experiments/results/figure_inputs/`, the htsim runners). We can produce figures. What we still cannot do is **prove which inputs produced the published ones** — across the seven data figures: 6a source-resolved but producer unknown, 6b / 6c / phases producer inferred from magnitude, 7a partly contradicted, 7b derived from constants, 7c unbacked entirely (B26). Every data figure therefore needs regeneration with a recorded chain; `FIGURES.md` is the checklist.
  Specific defects to carry: `plot_isopower.py` hardcodes fat-tree values (245.052 / 160.186 / 118.456 / 91.101) that are an **older pass** than the published 190 / 139 / 105, which live in `fig5ab_local.csv` and `isopower_fair_v2.csv`. The `COMPUTE = {mixtral8x7B: 102.0, llamaMoE: 75.0, qwenMoE: 70.0}` constants have **no traceable source** and must be re-derived from compute-only runs and carried as a CSV column, never a constant. And the committed `htsim_*.sh` runners all **predate** the RTO-floor / shortcut / `-mtu` / derived-queue corrections, so their outputs must never be mixed with post-correction CSVs — that is the figure-input analogue of `e2fc399`.
- **E47 [SETTLED]** Training graph coverage now spans EP 16 / 32 / 64 / 128 / 160 / 256, all `dp2tp1pp4`-family (real DP all-reduce + PP crossing panels) and all classified analytical. EP=32 (`llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100`) was generated for this, matching the EP=16 recipe in every parameter but `--expnum`. **Note when reporting the 16→32 step:** `EP×TP = 32 > 16` (panel size), so that graph deliberately spans two panels — it is the first past-the-boundary point, not a like-for-like EP scaling of the EP=16 row. This is what C28's per-system domain-boundary markers exist to show.


- **A37 [PROPOSED WORDING IS FALSE AS WRITTEN — see E43]** Compute-cost provenance sentence. The intent is right, but "attention costs are analytical **consistently across every graph**" is contradicted by a graph already in the set. Fix before it goes in: either name the exception or regenerate that graph analytically and restore the clean claim.
- **D35 [SETTLED]** The attention measurement mode is recorded per graph. `scripts/classify_measure_mode.py` writes a `.meta` sidecar beside every `.fbuf` and checks mode-consistency across curve-mates mechanically, so it stops depending on anyone remembering.
- **E43 [NEW — blocks A37]** One graph was generated with FlexFlow's **measured** attention path while every other is analytical:

  | graph | attention bytes (in / out / weight) | mode |
  |---|---|---|
  | mixtral8x7B_paper_dp2tp4pp4_ep8top2_L32_seq4096_mb8 | 4.027e8 / 8.389e6 / 1.091e8 | **measured** |
  | mixtral8x7B_paper_dp2tp4pp4_ep8top2_L4_seq4096_mb8 | 0 / 0 / 0 | analytical |

  Same model, same dp2/tp4/pp4, same seq4096 — differing only in layer count and in how attention was costed. **Any L4-vs-L32 layer-scaling comparison across these two is invalid.** Consistency holds within every other EP group (16, 64, 128, 160, 256 all analytical); EP=8 is the only mismatched group, and it also holds the two graphs with no dot-dump sidecar at all (mixtral8x22B _fixed and _validation), which remain UNKNOWN.

  This is the first provenance failure that lives in an **input artifact** rather than in a run, so no amount of run-side banner logging could have caught it: the simulation used exactly what it was handed and reported it accurately. Distinct sub-class for the §4b list, not a seventh instance of the same one.


- **E35 [SETTLED — corrects the record]** The iso-byte MTU result and its **mechanism**. At a byte buffer held at ~14.3 MB, mtu 9000 is *worse*, not better: inter 2400 goes 6.449 ms / 0 RTO → 24.151 ms / 1345 RTO, a 3.7× regression. The mechanism is **not** "fewer packet slots" (an earlier claim of mine, retracted): drops are byte-denominated (`queue.cpp:57`, `_queuesize + pkt.size() > _maxsize`). What *is* packet-denominated, and so 6× larger in bytes at mtu 9000, is the ECN marking threshold (`glassfb_topology.cpp:173`, `memFromPkt(_ecn_k_pkts)` → 450 KB vs 75 KB) and the initial congestion window (`tcp.cpp:182`, `_cwnd = 100 * _mss` → 900 KB vs 150 KB per flow, across ~1024 simultaneous flows). Jumbo frames lose because the incast burst is 6× bigger and marking fires 6× later into the same byte buffer. **Action: ECN_K should be byte-denominated or a fraction of the byte buffer** — this is a design lever, not only a note.
- **E36 [BLOCKED on 12872572, but the signal is already strong]** At the physically-derived corner, inter-panel provisioning barely matters. Partial results (EP=64 coding_prefill, intra 384, shortcut OFF, mtu 1500):

  | q | floor | inter 1600 | 2000 | 2400 | 3200 |
  |---|---|---|---|---|---|
  | 1000 | 100 µs | 13.052 (3776) | 13.052 (3776) | 13.816 (2217) | 13.816 (2217) |
  | 1000 | 1 ms | 14.747 (3776) | 14.747 (3776) | 13.174 (2217) | 13.174 (2217) |
  | 2000 | 100 µs | 14.147 (2828) | 14.147 (2828) | 13.214 (1292) | 13.214 (1292) |

  Two observations that bear directly on B11/B14/B15. (i) The whole 1600→3200 range spans **under 7%**, and the direction is **not monotonic** — at q=1000/100 µs more bandwidth is *slower*. (ii) 1600 and 2000 are bit-identical, as are 2400 and 3200, so the response is a two-level step, not a curve. If this holds across the remaining cells, the provisioning claim as written does not survive at derived transport in any form: **1600 GB/s (one MTP-16 at 100G/lane) suffices**, and the 200G/lane feasibility argument becomes unnecessary rather than merely unsupported. That is a *better* result for the paper's feasibility story than the one it replaces.
- **E37 [DEFERRED to future work — not before DATE]** Measuring a lossless bound is topology surgery, not a flag. My earlier "it's a flag, not a patch" claim is **retracted**; the probe aborted at `queue_lossless_output.cpp:68`, `assert(prev != NULL)`, because glass-FB never creates an upstream VirtualQueue on the path a packet takes — `alloc_src_queue` returns a plain `PriorityQueue` and `configureLossless()` is called only for `qt == LOSSLESS`. `FatTreeTopology` wires it end to end by comparison: LosslessInputQueue on the source queue (`fat_tree_topology.cpp:243`), on every switch-to-switch queue both directions (297–300, 364–367), `configureLossless()` per switch (395–398), and five route-construction special cases (443–497).
  **The blocker underneath is a modelling question, not an implementation one.** htsim's lossless machinery is Switch-centric — `configureLossless()` is a `Switch` method, PFC runs between switches — and glass-FB is switchless direct-connect with no `Switch` objects outside the `qt == LOSSLESS` branch. Physically the credit exchange lives at each link endpoint's EIC/PIC, hop by hop, which in htsim means making every glass node Switch-like with a LosslessInputQueue per incoming link. That is days of work with a modelling decision in the middle whose wrong answer would be indistinguishable from a right one — precisely the failure mode this project has been paying to avoid.
  **Future-work sentence, naming the open question rather than gesturing at it:** *"Modelling the fabric's credit-based flow control requires assigning the switch's PFC role to each link endpoint; we leave this to future work."*
  **Consequence for the claim:** "1600 GB/s suffices at derived transport" is a statement about DCTCP over lossy queues and the paper says so under A1. It remains the right feasibility claim — the structural incast at the gateway is transport-independent, and that is what provisioning must cover — but the absolute number carries A1's caveat explicitly.
  The inert `-queuetype` flag is **kept** (`0ae4ed2`): it makes the branches reachable for whoever does the work, and it adds a fourth banner line, so every run now records queue discipline alongside shortcut mode, RTO floor, MTU and queue bytes (D34).
- **E38 [RESOLVED — closes B24]** ARM A's width degeneracy is **real, not a shortcut artifact**. At mb=16 with the shortcut DISABLED: opt 400 → 187.403 ms, 512 → 185.237, 640 → 185.237 (896 pending). The old shortcut-ON row was 400 → 186.613, 512/640/896 → 185.652. So widening the intra optical tier past ~512 GB/s changes nothing either way, all rows at 0 RTO. The correct statement is **"intra-panel optical width saturates above ~512 GB/s at EP=16"**, which supports C31's 640 budget choice as sufficient rather than as a compromise. It does *not* license the stronger "intra is never the bottleneck" — that was only ever tested at EP=16 with inter pinned at 200.
- **E39 [OPEN]** `scripts/decompose_flows.py` reads `flow_size:` lines that are emitted *before* the shortcut test, so on any pre-`e2fc399` log it counts flows that never touched a wire and overstates the intra share by up to 2× (50% of flows eligible at EP=16, 12.5% at EP=64). A warning is committed on the script. **C28's FRED-Fig-10 decomposition must be regenerated from post-`e2fc399` logs** — the existing decomposition cannot be used.
- **E40 [SETTLED]** Every result CSV must carry a **byte** buffer column, not just `-q`. Because `-q` is in packets, two rows with the same `-q` and different MTU had different buffers, which is what produced instance #6. Applied going forward in `buffer_vs_mtu.csv` and `derived_corner.csv`.
- **E41 [SETTLED]** The buffer knee at the Ethernet default corner is sharp and then flat: at inter 2000, q=10000 → 46.028 ms / 68 RTO, q=12000 → 7.281 ms / 0 RTO, and q = 14000/16000/18000/20000/40000 all → 7.394 ms / 0 RTO. So the timeout regime ends between q=10000 and 12000 and nothing is gained above it. Useful for B13's "or buffering" clause and as evidence the 14.4 MB default sat just below a knee — a coincidence worth stating, since it is why the default looked catastrophic.

---

## Open questions for the user

1. **E37** — spend one smoke test on `LOSSLESS_INPUT_ECN` to turn the scope caveat into a measured bound? Recommended.
2. **E36** — if the corner confirms, the feasibility argument *improves* (100G/lane parts suffice) while the provisioning narrative weakens. Confirm that trade is acceptable before either is written.
