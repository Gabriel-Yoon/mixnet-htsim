# Energy accounting: what main.tex actually does, what it leaves open, and a proposal

Re-investigation of the Glass-FB energy figures, prompted by comparing them against the
2025 photonics literature (see `interconnect_parameters.md`). Three things came out of it:
one correction to how the risk was previously described, two genuine open choices that
change the numbers, and a new axis that is now computable.

---

## 1. What main.tex actually says

`main.tex` §Waveguide budget and `tab:power`:

| Quantity | Value | Where it comes from |
|---|---|---|
| One waveguide | 32 λ × 32 Gb/s = **128 GB/s** per direction | design assumption |
| Waveguides per GPU fielded | **~60** | panel-scale bump density, `\cite{panelscale}` |
| Per-GPU aggregate | 60 × 128 GB/s = **7.66 TB/s** | 8.5× NVLink4 |
| Link energy | **1.15–2.62 pJ/bit**, "passive link energy only" | `tab:power` |
| Interconnect power | **~70 W/GPU** | 7.66 TB/s × 8 × 1.15 pJ/bit = 70.5 W ✓ |
| Fat-tree side | ≥20 pJ/bit copper cable, switch power reported **separately** | `\cite{dragonfly}` = arXiv:2407.10290 |

**Correction to an earlier characterisation of this:** the paper does *not* hang everything on
1.15 pJ/bit. It already carries the range 1.15–2.62 and already reports the headline both ways
("~4× the power, easing to 1.4× at the conservative 2.62 pJ/bit"). The exposure is smaller than
a single-point 1.15 claim would be.

---

## 2. Open choice A — what the 1.15–2.62 pJ/bit covers

`tab:power` scopes Glass-FB's budget as **"passive link energy only"**. Lightmatter's Passage,
the closest shipping comparable, reports **4.3 pJ/bit** — but that total includes PIC, EIC,
laser *and* SerDes (its passive-ish off-package component alone is 1.1 pJ/bit, right on top of
our 1.15).

So the two numbers are not in conflict; they have different scopes. The risk is not that 1.15
is wrong, it is **asymmetry**: if Glass-FB is charged passive-link-only while the copper side's
≥20 pJ/bit includes its SerDes, the comparison flatters us by exactly the SerDes term.

Two ways to close it, in order of preference:

1. **State the scope in the caption and show the asymmetry is small.** Add the drive/SerDes term
   to both sides. Glass-FB's short-reach XSR SerDes is ~1 pJ/bit (<100 µm drive, HotI'25); copper's
   is ~5 pJ/bit (112G-LR with DSP). Adding both moves Glass-FB to ~2.15–3.62 and copper to ~25,
   i.e. the ratio *improves* slightly for us. This is the strongest fix: it removes the objection
   and costs nothing.
2. Quote 4.3 pJ/bit as an outer bound and show the headline survives. Weaker — it concedes a
   scope mismatch that does not actually exist.

---

## 3. Open choice B — per-NIC vs per-hop charging

`tab:power` charges each byte **once**, at the endpoint's link rate. A byte crossing a fat-tree
does not cross one link:

```
server -> edge -> agg -> core -> agg -> edge -> server        (fat_tree_topology.cpp)
  same edge switch ... 2 links
  same pod ........... 4 links
  cross pod .......... 6 links      <- dominates any large alltoall
```

Glass-FB's intra-panel alltoall is 1 hop (row/column peer) or 2 (relayed). So per-NIC charging
systematically under-charges the fat-tree by roughly its hop count.

**Precedent exists and it is already our own citation.** `\cite{dragonfly}` (arXiv:2407.10290,
Switch-Less Dragonfly on Wafers) computes energy per *delivered* byte from average hop count,
using 20 / 2 / 0.1 pJ/bit for long-reach / short-reach / on-chip hops. We cite this paper for
the 20 pJ/bit figure already; adopting its hop accounting alongside its number is consistent,
not novel.

**Recommendation: report per-NIC as the primary (it is what is already published in the draft)
and per-hop as a sensitivity row.** Switching the primary basis mid-revision invites "why did
this change?"; adding it as a sensitivity that *strengthens* the result is free.

---

## 4. Open choice C — lit waveguides vs fielded waveguides

The ~70 W/GPU figure charges all **60** waveguides the package fields
(60 × 1.024 Tb/s × 1.15 pJ/bit ≈ 71 W). The design lights only a fraction of them, and unlit
passive waveguides consume nothing.

**Two different "used" numbers exist and both are correct** — they answer different questions
(confirmed with the manuscript-revision session, whose `wg_budget.py` in LLMServingSim
`research/asp-dac-2027` `0862e73` carries the corrected model):

| number | what it is | what it is for |
|---|---|---|
| **~19.5 WG/GPU** | panel **average** | **energy / power** — this is what `WG_USED` is |
| ~26.6 WG/GPU | corner-GPU **worst case** | link **feasibility** capping in `wg_budget.py` |

Derivation of the average: a 4×4 panel has 24 distance-≥2 (optical) links — each row of 4
contributes 3 of its 6 links, times 4 rows + 4 columns. That is 48 endpoints over 16 GPUs =
**3.00 optical links per GPU on average** (corner 4, edge-middle 3, interior 2). At the current
400 GB/s design: 3.00 × 3 WG/dir × 2 = 18.8, plus 0.78 inter-panel = **19.5**. Distance-1 peers
ride the electrical RDL and consume no waveguide at all.

So main.tex's "~19 of 60" is right as written. (The old text reached it via 6 links × 3 WG where
the correct route is 3 optical links × 6 WG — same product, different reasoning.) The manuscript
number that *is* wrong is line ~659's "1600 GB/s ≈ 13 waveguides", which compares per-direction
against a both-directions budget; it should be 25 WG.

At the corrected-budget **wide** design (640 intra / 1600 inter) the average rises to
3.00 × 5 × 2 + 6.25 = **36.25 WG/GPU**. Both are selectable via `--design {current,wide}`.

Charging all 60 is conservative in our own disfavour either way, and should be *stated* rather
than left for a reader to derive.

### Do not read the provisioned current-vs-wide gap as an efficiency gain

Under `--budget provisioned` the advantage appears to rise from 3.12× (current) to 5.80× (wide)
at 1.15 pJ/bit. **That is a division artifact, not a physical effect, and must not be quoted.**

The pessimism multiplier is `WG_PROVISIONED / WG_USED`: 60/19.5 = 3.077 for current, 60/36.25 =
1.655 for wide, a ratio of 1.859. And 3.12 × 1.859 = 5.80 — the entire "gain" is that the
conservative overcharge shrinks, reproduced to three significant figures. The two numbers have
different denominators by construction and are not comparable to each other.

The physical reason is that `e_glass = bits × pJ/bit × hops` contains no waveguide-count term.
1.15 pJ/bit is a *dynamic* energy-per-bit figure; an unlit waveguide burns no dynamic energy.
`provisioned` is therefore a deliberate "charge us as if all 60 were saturated" upper bound, not
a model of the hardware. If asked whether 640/1600 consumes less energy per token than 400/200,
the correct answer is **no — it is identical** (verified: the `--budget used` rows for the two
designs are bit-identical).

**The correct framings, all of which are still favourable:**

1. **Energy per token is invariant to the provisioning choice.** This is a robustness property
   worth stating outright: the energy result does not move when the design point moves, so it
   survives the 400/200 → 640/1600 migration unchanged.
2. **What re-provisioning buys is latency at unchanged energy** — i.e. it improves GB/s per watt,
   which is already the paper's efficiency metric (`fig_energy`, the 46–101 GB/s/W envelope).
   The number to recompute for the wide design is GB/s/W, not µJ/token.
3. **Keep `provisioned` as a one-sided sensitivity check.** "Even charged for all 60 waveguides
   we still win by ≥3.1×" is honest and strong. Comparing two designs *within* that basis is not.

Consequence: re-provisioning has to justify itself on latency (Task 1). It gets no independent
energy justification.

Note this also resolves an inconsistency: an earlier iso-power sweep
(`serving_sweep_isopower.csv`) computed the per-GPU aggregate as
`1800 + 400 + inter_bw/G ≈ 2400 GB/s` — one adjacent link plus one far link plus a gateway
share. That is neither 7.66 TB/s (all 60) nor a correct count of a GPU's six intra-panel links.
It lands near the ~19-waveguide figure by coincidence, not construction. Any rerun of that sweep
should take its aggregate from this document instead.

---

## 5. New axis: energy per token

`scripts/energy_per_token.py` computes interconnect energy per token from the dispatch/combine
byte volumes the workload exports already carry, so it needs no new simulation. Results in
`experiments/results/energy_per_token.csv` (28 workloads: 4 phases × EP 8/16/32/64/128/144).

Sensitivity across every accounting choice above — **fat-tree joules ÷ Glass-FB joules**:

| charge | glass pJ/bit | budget | design | min | mean | max |
|---|---|---|---|---|---|---|
| per-NIC | 1.15 | used | — | 17.4× | 17.4× | 17.4× |
| per-NIC | 2.62 | used | — | 7.6× | 7.6× | 7.6× |
| per-hop | 1.15 | used | — | 9.6× | 19.1× | 32.1× |
| per-hop | 2.62 | used | — | 4.2× | 9.3× | 17.0× |
| per-hop | 1.15 | provisioned | current | 3.1× | 6.2× | 10.4× |
| **per-hop** | **2.62** | **provisioned** | **current** | **1.37×** | **3.02×** | **5.52×** |

`used` rows are bit-identical across `--design` (energy per bit carries no waveguide-count term),
which is the invariance property described in §4. The `provisioned` rows are quoted for the
**current** design only, on purpose: the wide design's provisioned numbers are larger only
because its overcharge denominator is larger, and quoting both side by side would present a
division artifact as an efficiency gain.

The bold row stacks *every* conservative choice simultaneously — the pessimistic end of the
paper's own pJ/bit range, the full 60-waveguide budget, per-hop charging that helps the fat-tree
nowhere, and the narrower current provisioning — and Glass-FB still wins by 1.37× at worst.

**This is the strongest defensible claim available from the data we have:** Glass-FB delivers
1.4–32× lower interconnect energy per token, and the direction never reverses under any
combination of the accounting choices that are genuinely arguable.

That matters because the latency picture is mixed — 15/48 configs beat fat-tree at iso-power
(`serving_sweep_isopower.csv`), concentrated at high bandwidth and small panel counts. Energy
per token is the axis where the design's actual thesis shows up unambiguously.

---

## 6. What is still missing

- **Cost.** Trade-press sourcing only (see `interconnect_parameters.md` §6). Supports an
  order-of-magnitude statement, not a table.
- **Switch power folded in.** Currently reported separately and excluded from the iso-power
  solve. Folding it in would strengthen the result further; it is disclosed as conservative
  today, which is defensible as-is.
- **Whether the comparison target should be fat-tree at all.** Nobody deploys a bare fat-tree as
  a scale-up domain; the real alternative is NVLink scale-up + fat-tree scale-out, and Glass-FB
  replaces the NVLink tier. That is a framing decision, not a data gap.
- **Re-run at the corrected intra-panel width.** The waveguide-budget fix above raises the
  buildable intra-panel link from 400 to 640 GB/s at the same power, and pins the inter-panel
  edge to a connector quantum of G × 400 GB/s (so G=4 → 1600 GB/s exactly). Every result in
  `serving_sweep*.csv` predates that, i.e. was run at 400/200 — narrower than the design can
  actually be built. Energy-per-token is unaffected (it scales with bytes and hops, not link
  width), but the latency results should be regenerated at 640/1600 before they are quoted.
