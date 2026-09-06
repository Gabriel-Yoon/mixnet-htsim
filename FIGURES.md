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
| `fig_thermal` | ANSYS MAPDL, run on PACE, **uncommitted** as of 2026-09-06 (`mixnet-sim/thermal/` on PACE only). Left panel: 4×4 full-package steady-state `thermal_panel_body.inp` via `run_panel_hq.sh` (NX=4, PGPU=700, FHOT=0.5, TCP_IN=55 TCP_RISE=20, HCP=70000, glass vs Si control) → `panhq_glass.rth` / `panhq_si.rth` (7 Jul, 49 MB each) — **solve succeeded but the CSV extraction failed silently** (MAPDL left output under the literal names `%CSVTILE%.csv` / `%CSVPLANE%.csv`; `panel_*.csv` never existed), so the published panel has no traceable producer until re-extracted. Note `_run_panel_small.sh` uses HCP=100000, not the paper's 70000. Right panel (PIC excursion ≤7.8 K, 13 Hz corner): from the single-stack transient decks in `mixnet-sim/thermal_pic/` (committed; `gen_pic_transient.py` → `pic_transient_*.inp` → `.rth` → `*_pic_transient*.csv` via POST26 `PRVAR`) and/or the PACE-only `stab_p*` stability sweep — exact deck to be recorded by the inventory. Being re-extracted and refined under Task #16. |

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
