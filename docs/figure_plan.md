# DATE 2027 result figures — plan (2026-09-06)

Budget: 6 pages → at most 4 data figures in the results + thermal + 2 design figures.
Style: `scripts/figures/paper_style.py` (one colour per system everywhere; dashed = bound;
numbers on bars; speedup axis). Every figure is drawn by `plot_paper.py` from
`experiments/results/paper/<paper_ref>.csv`, status=final rows only.

| # | figure | message (one sentence, = caption) | form | data |
|---|---|---|---|---|
| R1 | **The cliff** | Every fabric pays where an EP group first exceeds its domain; Glass-FB pays least and, once cabling follows the layout, stays ahead of the queued NVSwitch domain at every EP. | Iteration (ms, log) vs EP {16,32,64,128}; lines: Glass-FB (port map), Glass-FB mesh (light), NVL-64 pkt, HGX-8 pkt; dashed: NVL-64 / HGX-8 island bounds; vertical ticks at each domain boundary (8, 16, 64); model-per-point under the axis; right axis or inset: speedup over NVL-64 pkt. | cliff.csv |
| R2 | **Where the time goes** | The residual cost of crossing a panel is the cross-panel A2A tail, not throughput. | Stacked bars at EP=32 (and 64): compute / intra-panel A2A / cross-panel A2A / DP+PP / tail (max-FCT wait) per system; FRED-Fig-10 style. | decomp.csv (flowlog-based) |
| R3 | **Cabling × relay 2×2** | Neither correction helps alone; together they are 1.71× — cabling must match the traffic before the routing that exploits it can help. | Four bars at a common q (mesh/port map × relay off/on) + the quoted zero-timeout row; NVL-64 queued and bound as lines. | dse_cabling_2x2.csv + cliff_all |
| R4 | **Buffer vs tail** | More buffer stops drops but not starvation; makespan follows the max FCT, on both fabrics. | Two small panels: (a) NVL-64 k-sweep, (b) Glass edge 1600→3200 at EP=64; each: makespan (left axis, bars) + max FCT (right axis, line), RTO count as labels. | nvswitch_gates / edge_ep64 |
| R5 | **Energy** | Glass wins on the cross-domain tier by an order of magnitude and on whole-interconnect energy per iteration at either end of the pJ/bit brackets. | Two panels: GB/s/W (cross-domain tier) and J/iteration (bytes moved); dark = favourable pJ/bit end, light = conservative. | power.csv |
| R6 | **Microbatch** | With EP-aware placement the panel is insensitive to load. | Iteration vs mb {4,8,16,32} at EP=16, Glass vs NVL-64 pkt vs HGX-8. | mb.csv |
| T | Thermal panel (done) | The PIC is thermally the die. | Field map at the calibrated point. | thermal CSVs |

Placement in the paper: R1 + R2 + R3 as one double-column figure* (three panels); R4 + R5
as a second figure* (two/three panels); R6 folds into R1's inset or is dropped for space.
Drop from the current draft: fig_phases (number in text), fig_wgcross (merge into coupling),
fig_epplace (text), the old isopower/crossover/baselines/paneldse/copperfb PNGs.

What we borrow: MixNet — normalised grouped bars per model and bandwidth-sweep lines;
FRED — decomposition of end-to-end time into collectives and "speedup over the incumbent";
WATOS — numbers on every bar, config-ID labels; Rail-only — iteration vs bandwidth on a log
axis with the cost story next to it; Mozart — A/B/C ablation ladder as cumulative bars.
What is ours: solid-vs-dashed for queued-vs-bound on the same colour, and the tail (max FCT)
drawn next to the makespan wherever provisioning is the question.
