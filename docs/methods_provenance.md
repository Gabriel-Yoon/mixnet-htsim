# Simulation provenance: how we know the simulator did what we think

Draft for `main.tex` methodology. Not yet lifted in — paper edits are paused.
One paragraph for the paper, plus the record behind it.

---

## The paragraph (paper text)

> **Configuration provenance.** Simulator parameters that are set but never read
> produce results that are plausible, self-consistent, and wrong, and nothing in
> the output distinguishes them from correct ones. Over the course of this study
> six such settings were found, each after results derived from them had already
> been analysed. We therefore adopt a single rule: *a setting is not considered
> active until the run log shows evidence it was used.* Every binary prints the
> value of each configured parameter at startup — the intra-node shortcut mode,
> the retransmission-timeout floor, the packet size, and the queue size in bytes
> rather than packets — and every result table in this paper is traceable to a
> log carrying those lines. Where a parameter is derived rather than chosen, the
> derivation is given alongside it (Section~\ref{sec:transport}), because a value
> inherited from a simulator's defaults is not a modelling decision.

---

## The record behind it

Six instances, in order of discovery. Every one produced plausible numbers and
threw no error; none was found by the run failing.

| # | Setting | What went wrong | How it was found |
|---|---|---|---|
| 1 | Weight matrix | An 8×8 default silently wrapped by modulo for EP=32/64 | Inspection of expert placement |
| 2 | Packet size | `main_tcp_flat.cpp` defaulted to 9000 B, others to 1500 B, so identical `-q` meant a 6× different byte buffer | Cross-topology comparison that made no sense |
| 3 | Waveguide count | A per-direction count compared against a both-directions budget (`main.tex` ~line 659: "1600 GB/s ≈ 13 waveguides" should read 25) | Re-deriving the budget from the link rate |
| 4 | `GLASS_OPT_BW` | Never set in the published wide-design sweep commands, so every "wide" row silently used the 400 GB/s default | Noticing four widths gave identical makespans |
| 5 | Intra-node NVLink shortcut | `ffapp.cpp` completed any same-8-GPU-block flow at 600 GiB/s without entering the topology; 50% of flows at EP=16, and **100% of in-domain traffic** in the NVLink-domain configs, so `GLASS_ELEC_BW` was inert there | Counting `src_node`/`dst_node` pairs in the logs |
| 6 | `-q` versus MTU | `-q` is in *packets*, so a sweep varying MTU also varied the byte buffer 6×, confounding "jumbo frames help" with "more buffer helps" | Reading `queuesize` out of the log after the sweep |

Instance 2 and instance 6 are the same mismatch — packets versus bytes — found
first in the simulator's code and then, months later, in the design of a sweep
written *by the person who had fixed the code*. That is the argument for a
mechanical rule rather than vigilance.

### The rule, operationally

1. Every configurable parameter prints its effective value once at startup.
   Added so far: `Intra-node NVLink shortcut: {ENABLED|DISABLED}` (`6d3fae7`),
   `RTO floor: N us ({GLASS_RTO_MIN_US|default})` (`6fc7cb3`), `mtu`, and
   `queuesize` in bytes.
2. A result row is accepted only if its log carries those lines. Result CSVs
   record the banner value as a column, not just the intended setting.
3. A parameter added to the model gets its convention recorded beside it —
   per-direction or bidirectional, packets or bytes (see
   `interconnect_parameters.md` §4b).
4. Any new switch lands in two commits: one that adds it with the default
   unchanged and proves the old numbers reproduce bit-exactly, and one that
   changes the default. The two SHAs are the provenance boundary.

Rule 4 is what makes the record auditable rather than merely careful: `6d3fae7`
added the shortcut switch and reproduced the pre-patch cliff to the picosecond
(46 028 299 484 ps and 6 448 818 088 ps), and `e2fc399` flipped the default. Any
result predating `e2fc399` without `-disable-intra-shortcut` is pre-fix, and that
is decidable from the SHA alone.

### A worked example of the rule catching itself

The `GLASS_RTO_MIN_US` sweep's two baseline rows were produced by a build whose
log did not yet carry the default-path floor banner. The numbers were almost
certainly right, but under rule 2 they were not admissible, because nothing in
the log said which floor produced them. Re-running both configs on the current
binary reproduced 46 028 299 484 ps and 6 448 818 088 ps exactly, now with
`RTO floor: 10000 us (default)` present. The rule cost one re-run and converted
an assumption into a record.

### Six sub-classes discovered after the original six

The six instances above are all one failure: a setting that was configured but never read.
Six further failures have since been found that the banner rule provably **cannot** catch,
because in each the run used exactly what it was handed and reported it accurately.

| # | Sub-class | Instance | Why banners miss it |
|---|---|---|---|
| A | **Input provenance** | One task graph was generated with FlexFlow's *measured* attention path while every other used the analytical one, making a layer-scaling comparison across them unreadable | The mode is a property of the input file, not of the run; nothing at run time is wrong |
| B | **Figure without a producer** | `fig_baselines`, `fig_phases`, `fig_isopower` are committed PNGs whose source CSVs and plotting scripts were not in any repo; `fig_thermal` was drawn from a third run at h=100 000 while its caption says 70 000 | The chain from result to figure was never recorded at all |
| C | **Post-processing failed silently after a successful solve** | MAPDL wrote to files literally named `%CSVTILE%.csv` because the parameter never substituted; all four expected panel CSVs were absent, and a stale output from a *different configuration* sat in their place looking current | The solve succeeded and its `.rth` is correct; only the extraction failed, and it failed without an error |
| D | **Uncommitted code that keeps reapplying** | The flat port-cap implementation was written, built and run from a working tree and never committed; a commit referencing its `extern`s would not link from a clean checkout | `git -c rebase.autoStash=true pull --rebase` stashed and reapplied the files cleanly across many commits, so they stayed live in the tree while appearing in none of them |

| G | **A dead artifact is indistinguishable from an unborn one** | `experiments/results/paper/cliff_pkt.csv` sat header-only for days. The job meant to fill it aborted two seconds in, every time it was submitted, on an unbound `${tag}` in a `local` line under `set -u`. The packet-level NVSwitch cliff rows were on the must-have list and had never been measured | Nothing was wrong at run time, because there was no run. An empty output file is the *same* artifact whether the job has not been submitted, is queued, or has failed on every attempt — and "not started yet" is the reading that raises no alarm |
| F | **Partial instrumentation read as a census** | The used-pair set for regenerating the inter-panel port maps was extracted from ffapp's `flow_size:` print, which exists at **one** site — inside the all-to-all — while `set_flowsize()` is called from **nine**. The extract came out as 8 pairs, all `(2k, 2k+1)` with identical bytes: the EP pairs, with every DP and PP flow absent | Every line the log emitted was correct. Nothing was misconfigured, so no banner could report anything wrong; the log was silent about what it did not cover, and a set of 8 clean symmetric pairs looks exactly like a correct answer |

| E | **Runner script disagrees with the solve** | `run_panel_hq.sh` declares `HCP=70000` and cites Coenen for it; the solve it produced used **100000**, recovered from `panhq_glass.db` `*STATUS`. The solve has **no `.out` log** at all | Nothing at run time is inconsistent — the deck used what it was given; only the *script* claims otherwise, and scripts are read as documentation |

Sub-class E's rule, which is D's rule pointed at inputs rather than code:

> **The runner script is not evidence of what ran.** Recover boundary conditions and
> parameters from the solve artifact — `.db` `*STATUS`, a run banner, a `.meta` — never
> from the script that was supposed to have set them.

Applied: every thermal CSV row carries a `bc_source` column naming where its boundary
conditions were read from. It was only knowable here because MAPDL's `.db` retains scalar
parameters; had it not, the published figure's cold plate would have been unrecoverable.

**Sub-class D is the one that most resembles a correct state.** A working tree that reapplies an
uncommitted change across every rebase is, at runtime, indistinguishable from a committed one:
the binary builds, the results are real, and `git status` reports it only in a section nobody
reads while checking what was staged. The rule that follows is narrow and mechanical:

> **Attribution requires a rebuild from the SHA.** A result is attributable to a commit only once
> a binary built from that commit has reproduced it. "The committed source is identical to what
> ran" is the same *it must be fine* inference this document exists to refuse.

Applied: the port-capped flat rows (86.508 ms at EP=16, 67.821 at EP=32) are held **provisional**
until a rebuild from `1d10a42` reproduces them and the 410 025 604 ps gate bit-exactly.

Sub-class C's rule is the mirror image: **an output file existing is not evidence that the run
that was supposed to write it did.** Check the timestamp against the solve, not just the name.
The panel CSVs predated their own `.rth` files by three hours, which is what exposed them.

**Sub-class F is the one that produces the most convincing artifact.** The 8-pair set was
internally consistent, symmetric, and had the byte counts of a real measurement, because it *was*
a real measurement — of a subset nobody had established the size of. It was caught only because the
same run's relay dump named panel pair `(13,15)`, which the pair set did not contain. Without that
contradiction the maps would have been regenerated from it, cabling the 8 EP pairs, leaving every DP
and PP pair to relay, and reporting a clean generation.

> **An instrument must be shown to cover the population before its output is read as one.** Count the
> call sites, not the records. A log that never claims completeness will not warn you when it is
> partial, and a partial extract of a symmetric workload is symmetric.

Applied: the per-flow record now comes from `TcpSrc::set_flowsize` (`GLASS_LOG_FLOWS`), the single
choke point every collective passes through, rather than from any per-collective print. The
`decompose_flows.py` byte split read the same one-site source, so the EP=32 "inter = 48.7% of bytes"
decomposition is **withdrawn** pending regeneration; it described the all-to-all alone, not the
workload. Sub-class F also has a second instance in this repo: `used_pairs.py` reported its 8 pairs
without ever stating what fraction of flows its input covered.

**Sub-class G is the only one whose evidence is an absence.** Every other failure here left a
wrong artifact to be caught by reading it. This one leaves nothing, and nothing is what a
not-yet-run experiment also leaves. The absence sat in a directory of finished results, next to
files that were merely incomplete, and read as the same thing.

> **An output file must record that its job was attempted.** A run writes a `status=submitted`
> sentinel carrying the job id and start time before it does any work; reaching the end removes it,
> and dying rewrites it as `ABORTED` with the exit code. A file that never ran stays empty; a file
> whose job died says so.

Applied: `scripts/paper_csv.sh` provides `csv_open`/`csv_close`, and the sentinel is placed by
column *name* so it works across these CSVs' differing column orders. Retrofitted into the runners
not currently executing; `island_cliff.sh` is deliberately excluded because it accumulates rows
across invocations and `csv_open` truncates, which is a lifecycle decision rather than a mechanical
edit.

The helper's own first deployment failed this way in miniature: a wrong relative `source` path meant
`csv_open` was never defined, and the script carried on appending rows to a file with no header. It
was caught by checking the job's stderr rather than the CSV, which is the same rule as sub-class C —
**check the producer, not the product.**

### Scope limit

This rule establishes that a parameter was *read*. It says nothing about whether
its value was *right*: instances 3 and 6 were both settings that the simulator
used exactly as given, and were wrong anyway because the value handed to it had
been derived under the wrong convention. Banners are necessary, not sufficient;
the derivation requirement in rule 3 is what covers the rest.
