# Interconnect parameter sheet

Source data for building a defensible Glass-FB vs. Clos comparison: energy per bit,
switch power, per-GPU bandwidth, latency class, and cost — with provenance for each
figure, and notes on where a reviewer is likely to push back.

Compiled 2026-09-05. Companion artifact (same content, formatted):
https://claude.ai/code/artifact/82c04fbb-1bcd-447b-bcb1-09d89e072de6

Legend: **[E]** electrical/copper · **[O]** optical/photonic

---

## 1. Energy per bit

Total link energy unless the row says in-package or off-package — the split matters,
because our 1.15 pJ/bit has to be read against comparable *totals*.

| Technology | pJ/bit | Scope | Source |
|---|---|---|---|
| **[O] Glass-FB (this paper, blended)** | **1.15** | all links, per-GPU aggregate | main.tex `tab:power` |
| [O] Lightmatter Passage 3D interposer | 4.3 | total: PIC + EIC + laser + SerDes | HotI'25 Tab. III |
| [O] — its in-package component | 3.2 | in-package only | HotI'25 Tab. III |
| [O] — its off-package component | 1.1 | off-package only | HotI'25 Tab. III |
| [O] 2.5D CPO incl. host SerDes | 12 | total | HotI'25 Tab. II |
| [O] Linear pluggable optics (LPO) | 13 | total incl. host SerDes | HotI'25 Tab. II |
| [O] Pluggable optical module | 21 | total incl. host SerDes | HotI'25 Tab. II |
| [E] 112G-LR SerDes w/ DSP (host) | 5 | PHY only, no optics | ISSCC'21/'22 via HotI'25 |
| [E] Short-reach XSR SerDes @112G PAM-4 | 1 | PHY only, <100 µm drive | Tonietto, via HotI'25 |
| [O] Die-to-die OE chiplet adder | +0.5 | interface adder | UCIe, via HotI'25 |
| [O] TeraBIX transceiver @56G NRZ | 3.3–4.3 | transceiver | space-grade optics |
| [O] SiPh Tx, slow-light mod. @64 Gbaud | 0.78 | transmitter only (no Rx/laser) | arXiv:2506.04820 |
| [E] Scale-out class (paper's ≥20 assumption) | 16–20 | total, incl. retimers | HotI'25 Tab. I; SLDF |
| [O] Scale-up class (parity threshold) | <5 | total | HotI'25 Tab. I |

### ⚠ Credibility risk — read before defending 1.15

**1.15 pJ/bit is 3.7× better than the best _total_ number in the 2025 commercial-photonics
literature.** Lightmatter's Passage — a shipping 3D-stacked photonic interposer, the most
aggressive real product in this space — lands at 4.3 pJ/bit once PIC, EIC, laser and SerDes
are all counted. Its 1.1 pJ/bit off-package figure is the only published number near ours,
and it excludes the in-package 3.2.

Two defensible ways out: (a) state explicitly which components 1.15 covers and show the
excluded ones are genuinely absent in a glass-substrate design, or (b) quote a range with
4.3 as the conservative end and show the headline result survives it. A reviewer who knows
this literature will check.

---

## 2. Hop-count energy

The correction our current iso-power calculation is missing. A byte crossing a Clos fabric
pays link energy at *every* hop; a byte staying inside a Glass-FB panel pays once.
Switch-Less Dragonfly on Wafers computes exactly this way — citable precedent, not an
invention of ours.

| Hop class | pJ/bit | Notation | Source |
|---|---|---|---|
| [E] Long-reach / global (inter-cabinet) | 20 | H_l | arXiv:2407.10290 §V-C |
| [E] Short-reach (intra-cabinet, on-PCB) | 2 | H_sr | arXiv:2407.10290 §V-C |
| [O] On-chip / on-wafer | 0.1 | H_on-chip | arXiv:2407.10290 §V-C |
| [O] Intra-C-group average (their assumption) | 1 | — | arXiv:2407.10290 §V-C |

Transplanted to our comparison:

```
E_delivered_byte = Σ_hops ( bits × pJ/bit of that hop's link class )

  Glass-FB, intra-panel a2a ....... 1 hop    × 1.15 pJ/bit
  Glass-FB, inter-panel (mesh XY) .. 2–3 hops × mixed elec/opt
  Fat-tree, GPU→GPU ............... 3–5 hops × ~20 pJ/bit each
```

Under the current per-GPU-NIC formula the fat-tree byte is charged once. Charging per hop
is physically correct, has precedent, and moves the fair-speed solve substantially in our
favour — but it changes the paper's established `tab:power` method, so agree it first.

---

## 3. Switch power

Explicitly excluded from the paper's current iso-power basis (main.tex line 561:
*"excludes switch power above"*), disclosed as conservative in fat-tree's favour. These
numbers quantify how conservative.

| Device | Power | Capacity / notes | Source |
|---|---|---|---|
| [E] Broadcom Tomahawk 5 (BCM78900) | ~500 W | 51.2 Tb/s ASIC, 5 nm | TechInsights / EE Times |
| [E] — per QSFP-DD800 port | 30 W | no per-port active cooling | TechInsights |
| [E] NVIDIA Quantum-2 QM9700 (1U) | 1720 W | 64 × NDR 400G, 51.2 Tb/s | NVIDIA datasheet |
| [E] NVSwitch (per chip) | <100 W | ~5.5 W per bidir NVLink port | NVIDIA, via NextPlatform |
| [O] Passage saving per switch package | −1.5 kW | 200 Tb/s SLS switch package | HotI'25 §IV-C |
| [O] NVLink spine if built from pluggables | 20 kW | against a 120 kW rack budget | NVIDIA GTC'24, via HotI'25 |
| [E] GB200 NVL72 rack, total | 120–132 kW | 72 GPUs, 9 NVSwitch trays | NVIDIA / HPE |

The paper already notes switch power is *"independently substantial (up to 1.7 kW)"* — the
Quantum-2 figure above is exactly that number, so it is already consistent with the text.

---

## 4. Bandwidth & scale

| System | Per-GPU BW | Domain size | Source |
|---|---|---|---|
| **[O] Glass-FB panel (this paper)** | **7.66 TB/s** | 16 GPU / panel | main.tex `tab:power` |
| [E] GB200 NVL72 (NVLink 5) | 1.8 TB/s | 72 GPUs | NVIDIA |
| [E] Announced 2027 scale-up switch | 14.4 Tb/s | 144 GPU packages | NVIDIA GTC'24 |
| [O] Lightmatter Passage pod | 32 Tb/s | 512 GPU packages | HotI'25 §VI |
| [O] Huawei CloudMatrix | >1 Pb/s pod | 384 accelerators | SemiAnalysis'25 |
| [E] Scale-out class (per GPU) | 1.6 Tb/s | >100k GPUs | HotI'25 Tab. I |
| [E] Scale-up class (per GPU) | >12.8 Tb/s | <1024 GPUs | HotI'25 Tab. I |
| [O] Wafer C-group on-wafer (SLDF) | 12 TB/s bisection | 16 chiplets, 60×60 mm | arXiv:2407.10290 §V |
| [E] Electrical reach @224 Gb/s | ~1 m | DAC; tens of cm at 448G | HotI'25 §II-C |

### ⚠ Framing question this table forces

**Nobody deploys a bare fat-tree as a scale-up domain.** The real alternative to a Glass-FB
panel is an NVLink/NVSwitch scale-up domain with a fat-tree scale-out on top. Comparing
against fat-tree alone hands the competitor its expensive NVLink tier for free — precisely
the tier Glass-FB replaces. Both framings are defensible; they answer different questions.
Pick deliberately and say which.

---

## 5. Latency classes

| Path | Latency | Context | Source |
|---|---|---|---|
| [O] Scale-up domain | 100–250 ns | <1024 GPUs | HotI'25 Tab. I |
| [E] Scale-out fabric | 2–10 µs | >100k GPUs | HotI'25 Tab. I |
| [O] Optical link (wafer-scale study) | up to 200 ns | ~40× on-wafer short-reach | arXiv:2407.10290 §III |
| [O] On-wafer short-reach (implied) | ~5 ns | derived from the 40× above | derived |
| **[O] Glass-FB elec / opt / inter (ours)** | **100 / 300 / 500 ns** | simulator defaults | `glassfb_topology.cpp` |

Our 100 ns adjacent-hop default sits at the *top* of the scale-up band while representing an
in-package RDL link — our latency assumptions are already conservative against us, which is
worth stating explicitly rather than leaving for a reviewer to find.

---

## 6. Cost

The axis the paper has no version of. Weaker sourcing than the others (trade press, retail
listings) — supports an order-of-magnitude argument, not a precise table.

| Item | Figure | Notes | Source |
|---|---|---|---|
| [O] 800G optical module | $2,000–2,400 | retail listing range | GBICS / trade |
| [O] Optics $/Gbps trajectory | → ~$0.50 | projected by 2027 | trade forecast |
| [E] DAC copper vs optical | 2–3× cheaper | rate-dependent, short reach | trade |
| [O] Silicon-on-wafer bandwidth cost | <$1 per mm² | >800 GB/s per mm² | arXiv:2407.10290 §III-C |
| [E] Cable length, switch-based DF | 154K·E | at 279,040 processors | arXiv:2407.10290 Tab. III |
| [O] Cable length, switch-less DF | 73K·E | same scale, <half | arXiv:2407.10290 Tab. III |
| [E] Cabinets, Slingshot at scale | 2,180 | vs 545 wafer-based | arXiv:2407.10290 §III-C |

---

## 7. Normalisation precedent

| Paper | Normalisation | Scales | Headline |
|---|---|---|---|
| Switch-Less Dragonfly on Wafers (arXiv:2407.10290) | iso-bandwidth per link (all links = 1); energy compared separately via hop count | radix-16 (1,312 chips), radix-32 (18,560 chips) | cost + performance over switch-based Dragonfly |
| Accelerating Frontier MoE Training with 3D Integrated Optics (HotI'25, Lightmatter) | matched radix first (both 512), then architecture-specific radix (512 vs 144) | 512-GPU pod, 144-GPU pod | 1.4× matched radix, 2.7× native |
| **Glass-FB (ours, current)** | iso-power per GPU: aggregate BW × link pJ/bit, switch power excluded | EP 32/64, EP 128/144 | 15/48 vs fat-tree; 11/16 at 1600 GB/s |

Both precedents report at **two scales**, and both separate the bandwidth-matching question
from the energy question rather than folding them into one number. The Lightmatter pattern —
matched-radix result first, then native-configuration result — maps cleanly onto our EP=32
(fits one panel) vs EP=128/144 (native DeepSeek-V3 production) split.

---

## 8. Axis readiness

| Axis | Status | Note |
|---|---|---|
| Energy per bit | Ready | Needs the 1.15 pJ/bit scope statement resolved |
| Switch power | Ready | Consistent with the paper's existing 1.7 kW note |
| Hop-count energy | Ready | Blocked only on agreeing the method change |
| Bandwidth & scale | Ready | Forces the §4 framing decision |
| Cost | Thin | Trade-press only; order-of-magnitude claims only |
| Energy per token | **Missing** | Needs a sim run reporting J/token, not just makespan — the axis where our pJ/bit advantage shows directly |

---

## Sources

- Bernadskiy et al., *Accelerating Frontier MoE Training with 3D Integrated Optics*, HotI 2025 (Lightmatter) — https://arxiv.org/abs/2510.15893
- Feng et al., *Switch-Less Dragonfly on Wafers* — https://arxiv.org/abs/2407.10290
- *0.78 pJ/bit silicon slow-light transmitter* — https://arxiv.org/abs/2506.04820
- TechInsights, Tomahawk 5 — https://www.techinsights.com/blog/tomahawk-5-switches-512tbps
- NVIDIA Quantum-2 — https://www.nvidia.com/en-us/networking/quantum2/
- NVIDIA GB200 NVL72 — https://www.nvidia.com/en-us/data-center/gb200-nvl72/
- SemiEngineering, CPO power tipping point — https://semiengineering.com/co-packaged-optics-reaches-power-efficiency-tipping-point/
- *Heterogeneous Integration Technology Drives the Evolution of Co-Packaged Optics*, Micromachines 16(9) 2025 — https://www.mdpi.com/2072-666X/16/9/1037

Simulator defaults from `src/clos/datacenter/glassfb_topology.cpp`; paper figures from
`DATE_2027_GlassPhotonics/main.tex`.
