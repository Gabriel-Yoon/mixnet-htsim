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

**How large that fraction is, is itself under revision.** main.tex states "~19 of 60", but the
manuscript-revision session found that figure compares a *per-direction* waveguide count against
a *both-directions* budget (uni/bi mismatch); their corrected model puts the 400 GB/s design at
**~25 of 59.8 WG**. So the overcharge is ~2.4×, not the ~3.2× that "19 of 60" implies. Their fix
also raises the intra-panel cap (512 → 896 GB/s/dir, 640 with a 1600 GB/s edge reserved) — see
LLMServingSim `research/asp-dac-2027` commit `0862e73` and its `scripts/wg_budget.py`.

Either way the direction is the same: charging all 60 is conservative in our own disfavour,
which is defensible, but it should be *stated* rather than left for a reader to derive. Both
ends are in the sensitivity table below (`--budget used|provisioned`); `used` is parameterised
by `WG_USED` in the script, currently 19 and worth updating to 25 once their model lands.

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

| charge | glass pJ/bit | budget | min | mean | max |
|---|---|---|---|---|---|
| per-NIC | 1.15 | used (19 wg) | 17.4× | 17.4× | 17.4× |
| per-NIC | 1.15 | provisioned (60 wg) | 5.5× | 5.5× | 5.5× |
| per-NIC | 2.62 | used | 7.6× | 7.6× | 7.6× |
| per-NIC | 2.62 | provisioned | 2.4× | 2.4× | 2.4× |
| per-hop | 1.15 | used | 9.6× | 19.1× | 32.1× |
| per-hop | 1.15 | provisioned | 3.0× | 6.1× | 10.2× |
| per-hop | 2.62 | used | 4.2× | 9.3× | 17.0× |
| **per-hop** | **2.62** | **provisioned** | **1.34×** | **2.95×** | **5.38×** |

The bottom row stacks *every* conservative choice simultaneously — the pessimistic end of the
paper's own pJ/bit range, the full 60-waveguide budget, and per-hop charging that helps the
fat-tree nowhere — and Glass-FB still wins by 1.34× at worst.

**This is the strongest defensible claim available from the data we have:** Glass-FB delivers
1.3–32× lower interconnect energy per token, and the direction never reverses under any
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
