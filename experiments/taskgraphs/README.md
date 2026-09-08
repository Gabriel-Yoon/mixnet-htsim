# The four task graphs every quoted row is a simulation of

Committed here because they had no producer and no home in this repository. The
`.fbuf` files are what the runs actually loaded; they live in the mixnet-flexflow
tree and are too large to commit (4.5–48.5 MB). The `.txt` graphviz dumps and the
`.meta` configs are small, are what a reader needs to see the graph, and are here.

Verify identity by hash rather than by filename — the point of listing them.

| graph | .txt sha256 (16) | .fbuf sha256 (16) | .fbuf bytes |
|---|---|---|---|
| `llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100` | `a7e1f7390c89243a` | `f3f497bcf5dca734` | 4 552 136 |
| `llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100` | `eb38fe98a5d615ec` | `42a2d602617d6a59` | 9 499 376 |
| `qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100`  | `7f51fd106e5b8d5a` | `712b4528b4e59d41` | 20 720 856 |
| `arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100`  | `a170ddde9b2af596` | `643f9be5d9c80410` | 48 472 296 |

`.fbuf` path on PACE:
`/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results/<graph>.fbuf`

A fifth graph, `phi35moe_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb8_H100`, sits beside
them there and is **not** quoted anywhere in the paper; it is listed only so that
finding it in that directory does not suggest otherwise.

## What the `.txt` carries, and what it does not

Each node is `{ name | id | { ... } | { fwd | bwd | sync | secs } | { ... } |
{ in | out | weight | bytes } | { ... } }`. So it gives per-node **byte counts and
times**, and the dependency edges — enough for a critical path and a phase
breakdown by op class.

It does **not** give tensor shapes, and the nodes are shards whose size depends on
the dp x ep x pp partitioning. Do not try to recover a batch size or a token count
from them: that was attempted and abandoned, and the reason is in
`docs/methods_provenance.md` — the first softmax node is 8 192 bytes at EP=16 and
16 777 216 at EP=32, and reconciling them needs assumptions about dtype, about
which softmax is the router, and about sharding, none of which are recorded.

Tokens per iteration is sourced for exactly one of these graphs; see
`experiments/results/paper/tokens_per_iter.csv`.

## No producer

**No recorded command generates any of these files.** Neither this repository nor
the FlexFlow tree contains a script, a log, or a note that produces a
`*_paper_dp2tp1pp4_*` graph. The `.meta` sidecars record the configuration —
dp, tp, pp, ep, topk, layers, seq, mb, devices — and one generator log survives, for
`llamaMoE` EP=32 only. That gap is recorded as an instance of sub-class B in
`docs/methods_provenance.md`, pointed at the inputs rather than the figures.

Committing the artifacts does not close it. It means the graphs the paper's numbers
came from can at least be inspected and hash-checked by someone who does not have
the mixnet-flexflow tree.
