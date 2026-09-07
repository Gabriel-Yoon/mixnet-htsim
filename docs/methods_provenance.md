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

### A check is not trusted until it has been seen to fail

> **A check must be shown to go red on a known-bad input before its green is believed.** An
> unexercised check and a passing check are indistinguishable from their output, and the failure mode
> is the worse of the two: it reports success over exactly the condition it was built to catch.

Three instances here, each caught only because the check was deliberately provoked:

- **The drop counter.** `dropcount: 0` was reported by an instrument that had been added to one of
  six queue classes, so the zero meant *not counting*, not *no loss*. It became trustworthy only once
  the same binary returned **2 317 980** drops on a mesh control and **0** on the island. Every row in
  `quoted_row_drops.csv` now carries that validation in its note, so a zero there reads as measured.
- **The residue grep.** Two successive checks that the frozen-scripts snapshot contained no reference
  back to the working tree both printed a clean empty result, and both were incapable of printing
  anything else: the first filtered on `jobsnaps/`, which every match line contained in its filename
  prefix; the second compared a relative path against absolute matches. The real residue — three dead
  `$ROOT/scripts/` lines — appeared only on the third attempt.
- **The `model_name` patch.** A fix that matched a line-start form the call site never uses. It
  changed nothing and reported no error, and looked identical to a fix that worked.

The cost of the rule is one deliberately broken input per check. The cost of skipping it is a green
light over the defect itself, which is how sub-class F and the two vacuous greps above all began.

### Ten sub-classes discovered after the original six

The six instances above are all one failure: a setting that was configured but never read.
Ten further failures have since been found that the banner rule provably **cannot** catch,
because in each the run used exactly what it was handed and reported it accurately.

| # | Sub-class | Instance | Why banners miss it |
|---|---|---|---|
| A | **Input provenance** | One task graph was generated with FlexFlow's *measured* attention path while every other used the analytical one, making a layer-scaling comparison across them unreadable | The mode is a property of the input file, not of the run; nothing at run time is wrong |
| B | **Figure without a producer** | `fig_baselines`, `fig_phases`, `fig_isopower` are committed PNGs whose source CSVs and plotting scripts were not in any repo; `fig_thermal` was drawn from a third run at h=100 000 while its caption says 70 000 | The chain from result to figure was never recorded at all |
| C | **Post-processing failed silently after a successful solve** | MAPDL wrote to files literally named `%CSVTILE%.csv` because the parameter never substituted; all four expected panel CSVs were absent, and a stale output from a *different configuration* sat in their place looking current | The solve succeeded and its `.rth` is correct; only the extraction failed, and it failed without an error |
| D | **Uncommitted code that keeps reapplying** | The flat port-cap implementation was written, built and run from a working tree and never committed; a commit referencing its `extern`s would not link from a clean checkout | `git -c rebase.autoStash=true pull --rebase` stashed and reapplied the files cleanly across many commits, so they stayed live in the tree while appearing in none of them |

| J | **The run stopped before the quantity converged** | The tile transient reported a 26.159 K rise at `TEND = 0.05 s`. Its own 10–90 rise time is 33 ms, so the run stopped at ~1.5 rise-times and never reached its asymptote; a direct steady solve at identical boundary conditions gives 28.941 K, **10.6% higher** | The solve converged at every time step, the extraction worked, and the reported peak *is* the peak of what was simulated. Nothing is wrong except the stopping time, which no banner reports and no gate checks |
| I | **Two runs sharing one output path** | The simulator names its output directory from a **one-second** timestamp (`put_time(now_tm, "%m-%d-%H-%M-%S")`). Running six sweeps in parallel put two cells of different jobs into the same second, so both appended to one `fct_util_out.txt` and their lines spliced | Both runs are correct and both report success. The corruption is in a *third* file neither run is aware it shares, and it appears only in columns derived from it — `makespan` and `rtos`, read from each run's own stdout, stay right |
| H | **The schema moved under a writer that did not** | `island_ep64_qwenmoe.sh` appended rows positionally against a 36-column header. `fct_recompute.py` had since added nine columns to `cliff.csv` and the model/model_name split one more, taking the file to 46 — so 36 values were written under a 46-column header, `final` landed under a different column's name, and every field after `model` was one place out | A short CSV row is not a parse error; it is a row with empty trailing fields. Every tool read it without complaint, and the only visible symptom was a blank `status` on two rows out of eight |
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

**D's guard, added after it recurred twice in one session.** The rule above says a result is
attributable only once a binary built from that commit reproduces it. Nothing enforced the weaker
precondition — that the commit can be built *at all*. Twice the tree reached a state where targets
were unbuildable while their existing binaries kept producing results:

- the hierarchical all-to-all's `dynamic_cast<GlassFBTopology *>` put a typeinfo dependency into
  `ffapp.o`, which every binary links, while only the four glass targets linked `glassfb_topology.o`
  — twelve targets silently stopped building;
- the fix for *that* paired `glassfb_topology.o` with `flat_topology.o` and struck a latent duplicate
  definition of `check_non_null(Route *)` present in **eleven** translation units, dormant only
  because no binary had ever linked two of them.

Both were found by a build happening to fail, not by anything checking.

**D's third face: a rebuild that reports success and changes nothing.** The datacenter link rules
*linked* `$(OBJS)` — `../tcp.o`, `../ffapp.o`, `../queue.o` and the rest — but never *declared* them
as prerequisites, so make would not relink an existing target when a shared library source changed:

```
01:00  six queue classes edited
01:01  ../queue.o, ../prioqueue.o rebuilt
00:42  htsim_tcp_flat_drop unchanged — the build reported COMPLETED in 14 seconds
```

A control was then run against that binary and a conclusion drawn from code that was not in it. The
defect only ever bit *rebuilds*: a target whose output does not exist is always built, which is why
every instrumented binary in that session used a new target name and genuinely carried its change,
and why the single rebuild of an existing name silently did not. `$(OBJS)` is now declared on all 17
rules, and the gate detects the condition directly.

**The detector found twelve stale binaries, including the three that produced most of the quoted
rows** — `htsim_tcp_flat`, `htsim_tcp_nvswitch` and `htsim_tcp_glassfb_pm`, all predating the
current `libhtsim.a`. Those rows stand, and the argument is recorded here so it can be checked
rather than taken on trust. The four commits that touched the library after those builds are:

| commit | change | can it move a number? |
|---|---|---|
| `008f73c` | `GLASS_LOG_FLOWS` per-flow log | No — `getenv`-gated, no-op when unset |
| `008f73c` | hierarchical A2A retires zero-byte tasks | No — reachable only via `-a2a_hier` |
| `cc6efe8` | requested flow size added to the FCT record | No — an extra output column, not a simulation change |
| `24c99b3`, `c2c4d6b` | drop counters; `check_non_null` given internal linkage | No — counter increments and a linkage keyword |

None can alter a makespan or an RTO count on a run that sets neither the environment variable nor
the flag, so the stale binaries would produce identical numbers. **This is a reproducibility defect,
not a correctness one** — and the distinction is only available because the changes were enumerated
rather than waved at.

> **Staleness is reported, not fatal.** Hard-failing every submission over changes that provably
> cannot move a number would make the gate something to bypass, and a gate that is routinely
> bypassed has stopped being one. `STRICT_STALE=1` makes it fatal where that is wanted; link errors
> are fatal unconditionally.

The verdict is **mtime**, not hash: a binary older than an object it links is unambiguous, whereas
two links of identical sources need not be byte-identical (build ids, embedded paths), so a hash
difference alone would cry wolf on every run. The hash comparison is reported beside it as
information. On the first run both agreed on all twelve, which is reassuring and not something to
rely on.

> **Every paper row's job is submitted through a gate that links every target first.**
> `scripts/submit_paper_job.sh` runs `linkcheck.sbatch` with `sbatch --wait` and refuses to submit
> if any target fails to link.

The gate must not use `make all`: that would relink the binaries running jobs are executing, which is
exactly how a mid-sweep `make clean` destroyed a binary and invalidated two cells earlier in this
project. The Makefile's link outputs are therefore prefixed with `$(OUTDIR)`, and the gate links the
whole target list into a scratch directory. Verified on first run: **11 targets linked, and the
mtimes of every production binary were unchanged.** `SKIP_LINK_GATE=1` exists for a deliberate
override and requires saying so in the row's note.

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

G has a second form: a `status` field **asserted rather than derived**. Two rows carried
`status=final` and `status=sensitivity` while describing runs that had not happened as described.

The `dragonfly16` EP=32 row said `status=final` for a run whose own log reads
`GLASS_GW_PARALLEL=16 too large for panel_degree=15 and panel size=16; clamping to 1` — one gateway
on a 6400 GB/s link rather than sixteen at 400. The script *had* read that clamp into a variable, to
report `G`; it simply never gated on it, because the status field was a literal inside the row's
`echo`. The row even published `ports_lit=1` and `per_gpu_xpanel_gbs=25.0`, so the contradiction was
in the artifact all along, one column away from the word `final`.

Two `nvl64_ksweep` rows likewise carried `status=sensitivity` at `makespan 0.000` — meaning the run
never emitted `finished one iter`, having produced no iteration at all — and sat indistinguishable
from the three real cells beside them.

> **A status field must be computed from the run's own banner, never written as a literal.** Derive
> it from what the log says happened: clamp lines, relayed-pair counts, ports lit, whether an
> iteration completed, the timeout's exit code. A literal records the author's intention at the
> moment of writing the script, which is exactly the claim under test.

Applied: `dragonfly16.sh` records `blocked` when the topology clamps `GW_PARALLEL` below the
request and notes any disagreement between the caller's panel count and the one built;
`nvs_ksweep.sh` and `nvs_ksweep_hi.sh` derive `no_iteration` and `truncated`. The affected rows are
marked in place rather than deleted, and `plot_paper.py` filters on `status=final`, so a gated row
drops out of the figures instead of being drawn.

The helper's own first deployment failed this way in miniature: a wrong relative `source` path meant
`csv_open` was never defined, and the script carried on appending rows to a file with no header. It
was caught by checking the job's stderr rather than the CSV, which is the same rule as sub-class C —
**check the producer, not the product.**

**Sub-class H is the one that arrives through a correct change.** Nothing was wrong with adding
the FCT columns, and nothing was wrong with the runner when it was written; the defect was created by
the two being right at different times. It is the only failure here that no amount of care *at the
point of writing either piece* would have prevented — which is why the fix has to be structural
rather than a rule to remember.

> **Append to a shared table by column name, never by position.** A writer that positions its fields
> is correct only until someone adds a column, and the failure is silent when it comes.

Applied: `scripts/paper_csv.sh` provides `csv_row`, which reads the file's own header, places each
value by name, leaves unsupplied columns empty, and aborts on a key the header does not contain.
`island_ep64_qwenmoe.sh` uses it. `island_cliff.sh` still appends positionally, so it now refuses to
run at all when the file's header does not match its own `HDR`, and says what to use instead —
failing loudly being the acceptable form of the same protection when a rewrite is not warranted.

The two corrupted rows were **deleted and re-measured**, not repaired in place: reconstructing which
value belonged under which name would have been a guess dressed as a recovery, and the cells cost
sixteen minutes to run again.

**Sub-class I is created by scaling up, not by any change to the code.** The path was unique for
as long as runs were sequential; parallelising the sweeps made a one-second name collide. Nothing was
edited to cause it, and re-reading either script would never have shown it.

It was caught by a value that could not be a time: `maxFCT = 5644288.0000` ms in the `qfine` q=1000
cell. 5 644 288 is a **flow size in bytes** — the field offsets were from two different records
spliced together. A plausible-looking number would have gone through.

> **A run's outputs must be addressed by identity, not by clock.** Give every cell an explicit output
> path, and before any FCT column is written, check that no output directory was claimed twice.

Applied: `scripts/logdir_collisions.py` reads each run log's claimed directory and reports every one
claimed more than once; `scripts/mark_fct_status.py` sets an `fct_logdir` column per row to `clean`
or `shared_logdir`. The binary already accepts `-logdir`, so each cell now names its own.

The audit put the damage at **one row of one sensitivity CSV** — 23 collisions among 531 directories,
almost all in serving runs whose rows are not in the paper. Both FCT sources the paper quotes, the
NVL-64 k-sweep (`nvs_logs`) and the EP=64 edge study (`edge_logs`), were confirmed present in the
scanned set **and** absent from the collision list — checking that they were scanned, rather than
reading absence from a report as proof, being the whole point.

Contaminated rows are marked, never deleted: their makespan and RTO count remain valid, and only the
FCT columns are spliced. `fct_logdir` is a separate column from `status_fct` because that one already
records the payload/bracket mode, and one column carrying two meanings is how the `Q64` and `model`
collisions started.

**Sub-class J is the one that passes every check this document has so far imposed.** The
parameter was read, the banner was right, the artifact had a producer, the output path was its own,
the status was derived. The defect is that `TEND` was chosen before the response time was known, and
nothing re-examined it once the run had measured a 33 ms rise time and stopped at 50 ms.

> **A quantity that approaches a limit must be shown to have reached it.** Report the integration
> horizon in rise-times, not seconds, and gate on it: a transient quoted as a steady value needs its
> end time to be several times its own measured response.

It was caught only by a *cross-check against an independently computed value* — the R_int sweep's
perfect-contact reference disagreed with the published peak by 2.78 K, and chasing that disagreement
showed the reference was right and the published number short. Applied: both step runs re-run at
`TEND = 0.30 s` (~9 rise-times), and the R_int deck now prints its reference against the known value
so the comparison is recorded rather than done in someone's head.

J has a mirror image worth recording, because it arrived within the hour: **the reader started
before the run stopped.** The critical-path decomposition, pointed at the EP=64 logs while those runs
were still going, returned **33.547 ms** for glass — a perfectly well-formed critical path over the
tasks that had finished so far, from a cell whose completed siblings are 52–61 ms. Nothing about the
output looked partial; a partial task graph has a longest path just as a complete one does.

> **A derived product must check itself against a quantity its source reports independently.** The
> decomposition now compares its reconstruction with the makespan the run prints for itself, and
> refuses a mismatch with both numbers shown. That check is also what makes the completed rows
> trustworthy: they reproduce 75.542 and 119.397 ms exactly, so the walk is not fitting anything.

Note what the first version of that reference did: at `R = 1e-9 cm²·K/W` the layer conductivity
`k = t/R` is **10⁸ W/mK against glass's 1.2**, and the ill-conditioned solve returned a temperature
18.8 K *below* the true one — while the three real resistance cases sat within 0.73 K of each other,
which is what exposed it. A reference cell is not automatically trustworthy for being the "null"
case; it can be the only broken one.

Sub-class D also acquired a new instance worth recording: the hierarchical all-to-all's
`dynamic_cast<GlassFBTopology *>` put a typeinfo dependency into `ffapp.o`, which every binary links,
while only the four glass targets link `glassfb_topology.o`. Twelve targets — `nvswitch`, `flat`,
`fattree`, `mixnet`, `wafer`, `fc` and more — silently stopped being buildable, and kept working only
because their binaries predated the change. **The binaries on disk had ceased to be reproducible from
the committed source**, which is D's exact definition arrived at from the opposite direction: not
uncommitted code that keeps working, but committed code that cannot be rebuilt.

**Sub-class K is the only one where the code changed while it was being executed.** Every other
failure here is a fixed program producing a wrong or misread number. Here the program itself was
edited mid-run: `scripts/portmap_cliff.sh` was rewritten at 22:14 while job 12893533 was inside its
`pm_ep64_q57` cell, and the job then re-ran four of its five cells.

```
pm_ep16        once    206 s
pm_ep32_1221   twice   735 s, then 812 s     <- second pass resumes here
pm_ep32_842    twice   649 s, then 684 s
pm_ep64_qme    twice  1804 s, then 2096 s
pm_ep64_q57    twice  6814 s, then 6582 s    <- the edit landed inside this cell
```

`sacct` shows one job, started 20:50:28, running 5:43 continuously and never requeued, so this is not
SLURM restarting anything — it is one bash process reading a file that moved underneath it. **bash
reads a running script incrementally, by byte offset**, and a rewrite is truncate-then-write, so the
interpreter resumed at an offset that no longer meant what it had when the offset was recorded. That
the second pass restarts at the *second* cell rather than the first is the signature: a restart would
begin at `pm_ep16`.

The edit preserved the file length, and I had explicitly reasoned that this made it safe. It does
not. Length is irrelevant when the file is briefly zero bytes and the reader holds an offset into it.

> **A job must not read the working tree after it starts.** `submit_paper_job.sh` now copies the
> whole `scripts/` directory into `jobsnaps/<timestamp>_<sbatch>_<pid>/` at submit time, repoints the
> copies at the snapshot, and submits a rewritten sbatch that runs the copy. Editing a script during a
> run is then safe by construction rather than by remembering, and the snapshot is a record of exactly
> the code that ran, kept beside the commit it came from.

The whole directory is copied rather than the runner and its sourced helpers, because `paper_csv.sh`
is sourced by about forty runners and itself invokes `scripts/*.py`, and thirteen runners call Python
mid-run. At 696 K it is cheaper to copy everything than to trace which files a run might reach.

**No number moved.** The four duplicated cells agree to the digit across the two passes — 92.323 ms /
2047 RTOs, 125.666 / 8777, 51.478 / 103067, 155.509 / 101205 — with only wall time differing, which is
node contention. The plotters key one point per `(system, ep, q)`, so the duplicate rows draw once. The
accident is therefore an unplanned determinism check, and an unusually good one: the second pass ran a
*different build of the script* and reproduced the first exactly.

### Scope limit

This rule establishes that a parameter was *read*. It says nothing about whether
its value was *right*: instances 3 and 6 were both settings that the simulator
used exactly as given, and were wrong anyway because the value handed to it had
been derived under the wrong convention. Banners are necessary, not sufficient;
the derivation requirement in rule 3 is what covers the rest.
