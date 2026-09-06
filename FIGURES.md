# Figure provenance: paper PNG → script → CSV → task graph → measurement mode

Every data figure in `DATE_2027_GlassPhotonics/figs/` (and its ASPDAC predecessor) is
traced here to the script that drew it, the CSV the script read, and the FlexFlow task
graph(s) the CSV rows came from. Where the chain is **inferred** rather than recorded,
it says so. This file exists because, as of 2026-09-06, the PNGs were committed but
nothing behind them was: the plot scripts lived untracked on one laptop, the CSVs in
its `outputs/` directory, and no script on any machine writes a file named
`fig_*.png` — every paper figure was renamed by hand from a script's output.

Conventions: scripts are in `scripts/figures/`, their inputs in
`experiments/results/figure_inputs/`. Task-graph measurement mode (analytical vs
measured attention, see `docs/paper_todo.md` D35) is recorded per `.fbuf` in its
`.meta` sidecar on PACE; "analytical" below means every graph the row depends on is
classified analytical. Makespans in the figure CSVs were produced **before** the
2026-09 corrections (RTO floor, intra-node shortcut, transport derivation) and are
therefore superseded for any claim; they are kept so the published PNGs remain
reproducible as published.

## Data figures

| paper PNG | script → output name | input CSV(s) | graphs (mode) | provenance status |
|---|---|---|---|---|
| `fig_phases` | `plot_moe_6phase.py` → `moe_6phase_breakdown.png` | `paper_a2a_topo_compare.csv` (glass makespan normaliser) + per-graph `.txt` phase dumps | llamaMoE ep16 L4, mixtral8x7B **dp2tp4pp4** ep8 L4, qwenMoE ep64 L4 (all analytical) | **inferred**: the CSV has no graph column and no script writes it; identified as L4 by makespan magnitude (L32 seq4096 would be ~30× larger). Mixtral is the deprecated TP4 config → regenerate from the TP2/PP8 L8 graph (Task #2). |
| `fig_baselines` (Fig 6c) | `plot_mixnet_baselines.py` → `mixnet_baselines.png` | `mixnet_baselines.csv` (+ per-model `mixnet_baselines_*.csv`: llamaMoE, dbrx, mixtral8x7B, arctic, deepseekv2, qwen2_57b, qwen3_235b) | Table tab:configs trio: llamaMoE ep16, dbrx ep16, mixtral8x7B dp2tp4pp4 ep8 (analytical) | **inferred** from script inputs; same TP4 caveat → Task #2. |
| `fig_crossover` (Fig 6b) | `plot_microbatch_crossover.py` → `microbatch_crossover.png` | `glob mixnet_baselines_*.csv` (rows with an `mb` column) | llamaMoE ep16 mb 4/8/16/32 (analytical) | inferred from script inputs. Superseded by Task 1 ARM A/B (`crossover_wg_width*.csv`). |
| `fig_isopower` (Fig 6a) | **producer unknown** — `plot_isopower.py` → `isopower_compare.png` is the only isopower script, but its hardcoded `ft = {50: 245.052, 100: 160.186, 200: 118.456, 512: 91.101}` is an OLDER data pass that does NOT match the published figure | published values traced: fat-tree 50 → `fig5ab_local.csv` (189.454 @mb8), 100 → `fig5ab_local.csv` (138.831 @mb8), 200 → `isopower_fair_v2.csv` (105.322); glass 98 ms = the paper's LLaMA-MoE mb8 point | llamaMoE ep16 (analytical) | **RESOLVED as to source, UNRESOLVED as to producer**: main.tex §winbw's 190 / 139 / 105 ms are in the two CSVs, so the PNG was drawn from them by a script or edit that is not in the repo; the committed script is stale. Regenerate from `serving_sweep_isopower*.csv` (inference, corrected methodology) and the pending training iso-power run, with a recorded chain. |
| `fig_paneldse` (Fig 7a + inter-panel inset) | `plot_panel_dse_htsim.py` → `panel_dse_htsim.png`; `plot_interpanel_dse.py` / `plot_dse_multitopo.py` → `interpanel_dse.png` | `panel_dse_htsim.csv`; `interpanel_dse.csv`, `dse_multitopo.csv`, `isopower_compare.csv` | llamaMoE ep16 (analytical), mixtral8x7B dp2tp4pp4 ep8 (analytical) | inferred. The inter-panel "knees at 150–300 GB/s" panel is contradicted at mb≥16 and at derived transport (paper_todo B11) → re-run. |
| `fig_energy` (Fig 7b) | `plot_energy_final.py` → `energy_final.png` | none — derived from constants in the script (pJ/bit 1.15 / 2.62, per-fabric BW and power, `P_LASER`, `P_TUNE`, `GLASS_STATIC`, `NVL4_SWITCH`, `NVL5_SWITCH`) | — | derived figure; constants must match Table tab:power. Energy-per-token (`energy_per_token.csv`) is the corrected analogue. |
| `fig_copperfb` (Fig 7c) | **none in the repo** | **none in the repo** — no committed CSV has an FB-topology row at 100 GB/s (the only 100 GB/s rows are fattree / flat / fc), and no script or CSV contains the string "copper". `mixtral_fabric_sweep*.csv` was checked and ruled out: it is mixtral**8x22B** glass / nvl72 / gb200, drawn by `plot_fabric_breakdown.py`, not a paper figure. | should be llamaMoE ep16 (or mixtral8x7B) with the optical tier at 100 GB/s | **UNBACKED**: main.tex Fig 7c's "same FB topology in copper runs 1.8× slower than glass and 28% behind a fat-tree at 100 GB/s" has neither a script nor a data row behind it in any repo. Regenerate as a glassfb run with `GLASS_OPT_BW=100` (the "copper-FB @100" proxy) against 384/640, corrected methodology, and record the chain. |

## Non-data figures

| paper PNG | source |
|---|---|
| `fig_3d_node` | screenshot of `glass_panel_3d_4x4.html` (user-maintained; edit the HTML, not the PNG) |
| `fig_panel`, `fig_coupling`, `fig_wgcross`, `fig_epplace` | schematic drawings, no simulation input |
| `fig_thermal_panel` (left) | `scripts/figures/plot_thermal_panel.py` (defaults) → `thermal_panel_steady.png` | `experiments/results/thermal/panel_plane_glass_map1p15_h70k.csv` + `panel_map_tiles.csv` (variants design_map_1p15 / _si; d734171) ← `thermal_panel_map_body.inp` via `run_panel_map.sh` (die-only gate reproduces `panhq` .db 104.312/119.300 at h=100k; then per-tile PIC HGEN 14/36/58 W at 1.15 pJ/bit, h=70000, 55→75 °C) | committed chain. Glass outlet-corner PIC 135.1 °C, Si 129.0. Sensitivities in `panel_map_tiles.csv` (2.62 pJ/bit, h 50k/30k), `panel_h70k_tiles.csv` (die-only 70k), `panel_extra_tiles.csv` (Tin=40 → 120.16; h=100k → 120.55). The archived `panhq` solve (h=100k per its .db, die-only) and the ASPDAC PNG (h=100k, NDPT=6, no producer) are superseded. |
| `fig_thermal_transient` (REMOVED) | `thermal_pic/plot_pic_transient.py` → `fig_pic_mrr_transient.png` | `thermal_pic/*_pic_transient_L4seq4096.csv` | **Wrong stack for this paper** (user, 2026-09-06): these are the ICCAD/JETC OIO3D single-stack (GPU/EIC/aPIC, Coenen params) transients, not the glass panel stack. Removed from the DATE draft together with the ≤9 K / 0.72 nm numbers. The ASPDAC "≤7.8 K, ~13 Hz" figure likewise has no committed producer. A glass-panel-stack transient (map body, one tile, idle↔TDP swing) is pending. |

## Scripts in `scripts/figures/` that are not paper figures

`plot_topo_compare.py` (reads `paper_topo_compare.csv`, which was never generated — its
graph list included the one measured-attention Mixtral L32 graph, now excluded),
`plot_nvl72_scale.py`, `plot_htsim_glassfb.py` (hardcoded mixtral8x22B numbers, no paper
figure), `trace_breakdown.py`, `traffic_volume.py`. `plot_topo_compare.py` also hardcodes
`COMPUTE = {mixtral8x7B: 102.0, llamaMoE: 75.0, qwenMoE: 70.0}` ms labelled "measured"
with no traceable source; compute floors must come from compute-only runs written to a
CSV column, never from a constant.

## Run scripts moved into `scripts/`

`htsim_topo_compare.sh`, `htsim_interpanel_dse.sh`, `htsim_inter_bw_sweep.sh`,
`htsim_mixtral_sweep.sh`, `htsim_mixnet_baselines.sh`, `htsim_mixnet3_sweep.sh`,
`htsim_nvl72_crossover.sh`, `ep128_domain_test.sh`, `ocsfc_artifact_test.sh` — the
htsim invocations that produced the figure CSVs above. All predate the 2026-09
corrections: none sets the RTO floor, `-disable-intra-shortcut`, `-mtu`, or derived
queue sizes, and their outputs must not be mixed with post-correction CSVs.

## Machine-specific paths (known, deliberate)

Every script under `scripts/figures/` and the `htsim_*.sh` runners carry absolute paths
from the laptop they ran on (`/Users/.../outputs/fabric_plots`, `/tmp/*.txt` side files,
`/storage/...` on PACE). They are committed **as they ran**, because the point of this
commit is provenance, not portability — rewriting paths would change the artifact being
recorded. To run one elsewhere, set the `FP` / `OUT` / `TG` constants at the top of the
script to your copies of `experiments/results/figure_inputs/` and the task-graph
directory. Any *regenerated* figure must use a script with those paths parameterised
(env var or CLI flag), so the next FIGURES.md row can point at a runnable command.

## Rule going forward

A figure is admissible only if this table has a row for it whose script, CSV and
graph `.meta` all exist in the repo, and whose CSV rows carry `workload_type` and
`ep_source`. Regenerating a figure means updating its row, not just the PNG.

## DATE 2027 regeneration (pending data)

`scripts/figures/plot_paper.py` draws every data figure of the DATE draft from
`experiments/results/paper/<paper_ref>.csv` (schema in the script header; only rows with
`status=final`). Figure ← paper_ref: `fig_cliff` ← cliff; `fig_decomp` ← decomp; `fig_beyond` ← beyond
(+ serving_secondary); `fig_mb` ← mb + load; `fig_ladder` ← ladder; `fig_energy` ← power. Until a CSV
exists the script prints `skip: missing …` and the DATE repo carries the watermarked ASPDAC PNG.
