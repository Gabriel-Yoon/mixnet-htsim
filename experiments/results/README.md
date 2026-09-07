# Anything in this directory written before 2026-09-07 10:01 is pre-fix

`9ac4f76` (merging `d1d7141`, *link rate: stop truncating picoseconds-per-byte to an
integer*) landed at **2026-09-07 10:01 -0400**. Before it, `Queue::Queue` computed

```cpp
_ps_per_byte = (simtime_picosec)((pow(10.0, 12.0) * 8) / _bitrate);
```

which in GB/s is `floor(1000 / rate)`. Any link whose rate did not divide 1000 ran
faster than its stated rate, and a rate above 1000 GB/s ran in **zero time**:

| stated | ps/byte | effective | error |
|---|---|---|---|
| 50, 100 | 20, 10 | exact | — |
| 112.5 | 8 | 125 | +11.1% |
| 384 | 2 | 500 | +30.2% |
| 400, 450 | 2 | 500 | +25.0%, +11.1% |
| 640 | 1 | 1000 | +56.3% |
| 900 | 1 | 1000 | +11.1% |
| 1600, 1800, 2400, 3200 | **0** | **unbounded** | — |

## What that means for the files here

`experiments/results/paper/` is re-measured, gated and stamped: every row there
carries `link_rate_fixed` and `binary_sha`, `gate_quotable.py` refuses an affected
fabric without the proof, and `build_cliff_table.py` / `build_buffer_sweeps.py`
apply the exclusion themselves rather than leaving it to step order.

**Nothing in this directory outside `paper/` is gated, stamped, or re-measured.**
`gate_quotable.py` globs `paper/*.csv` and cannot see one level up. As of
2026-09-07 that is every file here dated 09-05 or 09-06, including five that are
untracked — `edge_ep64.csv`, `beyond64.csv`, `flat900_ep64.csv`,
`flat_portcap.csv`, `nvl_latency_model.csv`.

No figure reads them: `scripts/figures/plot_paper.py` loads only from `paper/`.
They are kept because a re-run may want their configurations, not their numbers.

## Two specific traps in them

**`edge_ep64.csv` sweeps a variable that had no effect.** Its three cross-panel
edge rates — 1600, 2400 and 3200 GB/s — all truncate to zero ps/byte, so the edge
cost nothing at any of them. Consistent with that, the *faster* edge is the slower
row throughout (qwenMoE 105.004 ms at 1600 against 2716.669 at 3200). The claim it
was cited for is withdrawn in `docs/hierarchical_a2a_design.md` §1.

**`flat_portcap.csv` and `flat900_ep64.csv` are one column wide on every capped
row.** The writers extracted the banner with `awk '{print $1}'` from
`Flat port cap: ENABLED, one 50 GB/s egress port per node, ...`, and the first
field is `ENABLED,` — the sentence's own comma — pasted unquoted into a CSV. On
those rows `makespan_ps` is empty, picoseconds sit under `makespan_ms`,
milliseconds under `rtos`, and the RTO count under `wall_s`. The writers are fixed
(`portcap_gate.sh`, `flat900_ep64.sh`); these files predate the fix and were not
rewritten.

See `docs/methods_provenance.md`, sub-classes L, M and N.
