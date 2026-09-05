# Simulation inputs and results

This directory holds the actual data behind the multi-gateway / mesh-mode EP>panel
experiments: the LLMServingSim-derived task graphs used as simulator input, and the
result CSV from running them through htsim.

## `pb_workloads/`

16 workloads (`decode`, `coding_prefill`, `chat_prefill`, `agentic_prefill` x
EP in {8,16,32,64}), each as both:
- `json/<workload>_ep<N>.json` — LLMServingSim's real GateRouter routing + profiled
  H100 MoE compute latency for that workload/EP, exported via
  `LLMServingSim/scripts/export_decode_ep_sweep.py`.
- `pb/<workload>_ep<N>.pb` — the same data converted to a `TaskGraphProtoBuf` graph
  (`mixnet-htsim/src/clos/gen_decode_block.cpp`), ready to feed to htsim directly.

Regenerate from scratch (from the LLMServingSim repo root):
```bash
python3 scripts/export_decode_ep_sweep.py --model deepseek-ai/DeepSeek-V3-0324 \
    --phase decode --batch 128 --tag decode --eps 8 16 32 64 --out-dir <out>/json
python3 scripts/export_decode_ep_sweep.py --model deepseek-ai/DeepSeek-V3-0324 \
    --phase prefill --total-len 4096 --tag coding_prefill  --eps 8 16 32 64 --out-dir <out>/json
python3 scripts/export_decode_ep_sweep.py --model deepseek-ai/DeepSeek-V3-0324 \
    --phase prefill --total-len 1024 --tag chat_prefill    --eps 8 16 32 64 --out-dir <out>/json
python3 scripts/export_decode_ep_sweep.py --model deepseek-ai/DeepSeek-V3-0324 \
    --phase prefill --total-len 8192 --tag agentic_prefill --eps 8 16 32 64 --out-dir <out>/json
# then, from mixnet-htsim/src/clos (build gen_decode_block first -- see its header comment):
for j in <out>/json/*.json; do ./gen_decode_block "$j" <out>/pb/$(basename "$j" .json).pb; done
```
The ISL values above (4096/1024/8192 for coding/chat/agentic) are a documented choice
for representative short/medium/long prompt lengths, not pulled from a named dataset.

## `results/serving_sweep.csv`

Glass-FB, `GLASS_INTER=mesh` (the physically-honest 4-edge-per-panel topology), swept
over every workload x {EP=32 (2 panels), EP=64 (4 panels, 2x2 mesh grid)} x
{400,800,1600 GB/s inter-panel bandwidth} x {G=1 (today's single gateway), G=4
(multi-gateway spreading, same total bandwidth)}. Columns: `makespan_ps`/`_ms` (total
iteration time), `rtos` (retransmission-timeout count, a congestion-severity proxy).

Exact command per row (run from `src/clos/datacenter`):
```bash
GLASS_INTER=mesh GLASS_INTER_BW=<bw> GLASS_GW_PARALLEL=<G> \
  ./htsim_tcp_glassfb -nodes <32|64> -flowfile ../../../experiments/pb_workloads/pb/<workload>_ep<32|64>.pb \
  -q 10000 -weightmatrix ../../../test/wm_ep<32|64>.txt
```

**`-weightmatrix` and `-q` are not optional** -- see Gotchas below.

## `results/baseline_sweep.csv` -- not included here

fat-tree / `htsim_tcp_flat` (full-bisection-style) comparisons for the same 16
workloads x {EP=32, EP=64} x {400,800,1600 GB/s} were started, then handed off
mid-run to continue on PACE (faster turnaround there). Not pushed in a partial
state to avoid anyone mistaking it for a finished, reviewed result.

## Gotchas found while producing `serving_sweep.csv` (read before rerunning anything)

Both of these are real footguns, not stylistic choices -- they silently changed
results in earlier (unpublished, since-discarded) runs of this same sweep:

1. **`load_taskgraph_protobuf` always applies a weight-matrix skew**, even for the
   `.pb`/serving path (`ffapp.cpp`, `weight_matrix[fn_expid % size][tn_expid % size]`)
   -- it is not bypassed just because the `.pb` already carries real aggregate byte
   counts. `main_tcp_glassfb.cpp`'s *default* `-weightmatrix` is a hardcoded 8x8
   matrix (`test/num_global_tokens_per_expert.txt`). Omitting `-weightmatrix` for
   EP=32/64 silently wraps that 8x8 matrix via modulo -- a meaningless periodic
   artifact, not a real skew model. Always pass the EP-sized matrix explicitly:
   `-weightmatrix ../../../test/wm_ep<N>.txt`.
2. **`htsim_tcp_flat`'s default packet size is 9000B vs 1500B for
   `htsim_tcp_fattree`/`htsim_tcp_glassfb`**, so the same `-q` value gives `flat` a
   6x bigger byte buffer (`queuesize = q * packet_size`) -- a large, unfair edge for
   any fat-tree/flat vs. glassfb comparison. Two fixes exist:
   - Compute `-q` per binary to match a common byte target (what `serving_sweep.csv`
     does: `-q 10000` at 1500B/pkt = 15,000,000B).
   - Or pass `-mtu <bytes>` explicitly to every binary (added after this CSV was
     generated -- overrides the compile-time packet size directly, so the same `-q`
     means the same bytes everywhere: `-mtu 1500 -q 10000` on all three). Prefer this
     for any *new* sweep; it's less error-prone than computing per-binary `-q`.

## Reading these against the paper

- **EP=32 mesh numbers are numerically identical to the earlier fb2-mode numbers** —
  with only one possible neighbor panel, mesh and fb2 connectivity coincide, so no
  new run was needed to validate that point; it's included here for a complete,
  self-consistent table.
- **EP=64 is the interesting case**: on the true 4-edge mesh (not fb2's more generous
  full-row/column graph), each panel is limited to G<=4 (the fixed 4-GPU edge pool),
  and the 4 panels of one EP domain form a 2x2 grid where the diagonal pair is 2 hops
  apart (dimension-order routed) rather than fb2's assumed 1 hop everywhere.
- The 512-GPU full-scale training numbers (fat-tree / full-bisection / Glass-FB
  @200GB/s and @1600GB/s) are **not** in this directory yet -- that run is orders of
  magnitude slower (hours, due to severe congestion at 512 nodes) than anything
  here and is tracked separately.
