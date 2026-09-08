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

Five instances here, each caught only because the check was deliberately provoked:

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
- **Three `.gitignore` rules that were never rules.** After a `git add` over `src/clos` swept a
  220 MB EP=128 log directory into the index, three patterns were added to keep run logs out --
  each with its explanation after the pattern on the same line. **gitignore has no
  trailing-comment syntax**, so every one of those rules was the path *plus the spaces plus the
  `# ...` text*, and matched nothing. Git reports no error for this; `git status` looks the same
  whether a directory is ignored or merely untracked, so the guard read as working for as long as
  nobody tried to stage those paths. `git check-ignore -q` on all five log directories is now the
  test, and it is run after the change rather than the rules being re-read.
- **A red test that came out green, twice, because the perturbation was not one.** Validating the
  hop dump against the real runs' hop logs, the first deliberately-wrong configuration was
  `GLASS_DIM_A2A=0` and it produced *identical* tier bytes; so did `GLASS_EP_PLACE=0`. Neither
  proved the check was vacuous. Dimension-ordered routing chooses between two intra-panel relays
  that give a 2-hop path the same tier composition -- it changes which links carry the bytes, not
  how many hops of each tier -- and placement decides which *rank* sits on which node, while the
  dump is driven by node ids straight out of the flow log. Removing the port map moved 172 hop
  triples and the check went red.

  > **A red test that passes has told you about your perturbation, not about your check.** The
  > temptation is to read the green as "the check is broken" or, worse, as "the check is fine, and
  > so is everything else". Both readings skip the actual finding, which in this case was a fact
  > about the fabric worth keeping: the tier split is a property of the topology's geometry and
  > cabling, not of the routing policy inside a panel or of where the ranks were placed.

The cost of the rule is one deliberately broken input per check. The cost of skipping it is a green
light over the defect itself, which is how sub-class F and the two vacuous greps above all began.

### Thirteen sub-classes discovered after the original six

The six instances above are all one failure: a setting that was configured but never read.
Thirteen further failures have since been found that the banner rule provably **cannot** catch,
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

| M | **A guard scoped to one producer** | `gate_quotable.py` defers to a ladder-level verdict so it will not re-judge which rung came first -- but the test was `quoted_by == "collector"`, and `build_calib.py` applies the same rule and did not stamp the field. The gate re-judged all 96 calibration rows one at a time, took 16 quotable rows to 76, and the figure's tiebreak then drew the *fastest* clean rung: **19.43%** efficiency where the rule gives **17.96%** | Every row is measured, every value is right, and the gate applied its own rule correctly. The defect is that the rule is the wrong one for that file, and the mechanism written to say so was keyed to a name rather than to a property |
| N | **The producer discarded the key that told its experiments apart** | `collect_rungs.py` groups rungs into walks by `(system, ep, mb, variant)`, then writes the row without `variant`. Four glass EP=32 rows -- plain `g32` 77.918 ms, skew-1.2 `sk1p2` 74.814, skew-2.0 `sk2p0` 81.419, hierarchical `hier32` 202.683 -- reached R1 as one cell, each correctly quotable as the first clean rung of its own walk, and the figure drew the lowest: **a workload-skew configuration plotted as glass's headline EP=32 point against incumbents measured unskewed** | Every row is right and so is every verdict on it. The distinction existed only inside the producer, for the length of one loop, and nothing downstream could see that four rows describing one (system, ep, mb) were four different experiments |
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

**Sub-class L is the one the paper's own numbers were built on.** Every sub-class above
concerns whether a measurement can be attributed, trusted, or reproduced. This one is different:
the simulator was computing the wrong answer, correctly and consistently, for every link whose
rate did not divide 1000 GB/s.

`Queue::Queue` computed the service time as an integer:

```cpp
_ps_per_byte = (simtime_picosec)((pow(10.0, 12.0) * 8) / _bitrate);
```

In GB/s that is `floor(1000 / rate)`, so:

| rate GB/s | ps/byte | effective | error | where |
|---|---|---|---|---|
| 50 | 20 | 50 | exact | NVL-64 chip link |
| 100 | 10 | 100 | exact | NIC tier |
| 112.5 | 8 | 125 | +11.1% | HGX-8 |
| 400 | 2 | 500 | +25.0% | glass inter-panel (port-map mode) |
| 384 | 2 | 500 | +30.2% | glass optical |
| 1800 | **0** | **unbounded** | — | glass electrical |

A zero means `drainTime` returns zero for every packet: the tier carrying 39.5% of glass's bytes
at EP=64 had **no transmission time at all**.

> **A rate that cannot be represented exactly is not a rate.** Service time is now computed per
> packet in exact integer arithmetic, `(size*8*10^12 + bitrate/2) / bitrate`, rounded to nearest,
> so the error is at most half a picosecond per packet rather than up to one per byte — 333 ps on
> a 1500-byte packet at 450 GB/s, which is the entire 11%.

**It was found by building the calibration the paper did not have.** No internal check could have
caught it: every run was self-consistent, every banner reported what was configured, every walk
reproduced its own makespan to the picosecond, and the defect had been present for every row ever
measured. It surfaced only on comparing an 8-GPU all-to-all against published hardware numbers and
finding 498 GB/s coming out of a port stated at 450. Three rates then confirmed it —
249.9 / 499.5 / 998.1 against stated 225 / 450 / 900 — and the glass fabric confirmed it a second
way: `ELEC_BW` 1800 and 2000, which both truncate to zero, returned **86750404764 ps, identical to
the picosecond**, which cannot happen if the tier costs anything at all.

**The direction was the uncomfortable one.** The fabric the paper advocates had the largest
unearned advantage: one tier unbounded, another 30% fast, a third 25% fast, while the incumbent's
chip link at 50 GB/s was exact. Correcting it moved glass +1.0% / +3.1% / +9.4% at EP 16/32/64 and
left the incumbents untouched, and it reversed one published claim outright — §dse's "the
dimension-ordered route hurts without the right cabling" was an artefact of mesh cabling loading
the tier that ran fast.

> **What survives a correction is worth more than what it replaced.** Every other conclusion held:
> the microbatch sensitivity, the energy separation, HGX-8's buffer-invariant spurious timeouts,
> the non-monotonic buffer-vs-tail shape. They are now measured on a simulator whose links run at
> their stated rates, and the one claim that did not survive was found before submission rather
> than after.

Two derived rules came out of the re-run, both about parallelism rather than physics. Running every
rung of a walk simultaneously broke an assumption that had been true by construction — a sequential
walk stopped at its first timeout-free rung, so "zero timeouts" and "first zero-timeout rung" were
the same row, and with all rungs measured they are not. And a derived table must carry its sources'
provenance columns: twice, a builder constructed rows with a fixed key set, dropped
`link_rate_fixed`, and let the next gate pass mark every post-fix row as pre-fix — once making the
consolidated table disagree with the file it was built from, and once making R4 draw the pre-fix
39.395 ms in place of 43.088.

**Sub-class M is the one the guard against it had already been written for.** The gate that
applies the vanishing-timeout rule row by row carries an explicit deferral, and its comment states
the reason exactly: a per-row pass "cannot know which rung came first, so its per-row rule would
mark every clean rung quotable and let a walk be quoted far above its vanishing point." That is a
correct description of a property. The code tested a name:

```python
if (r.get("quoted_by") or "").strip() == "collector":
```

`collect_rungs.py` was the only producer stamping the field when the deferral was written. When the
calibration table arrived it applied the same ladder rule -- first timeout-free rung per
(variant, M) -- and stamped nothing, so the gate saw 96 unattributed rows and did what it does.
The blast radius was one column: `quotable` went from 16 rows to 76, four to six of them per
ladder, all of them genuinely clean.

> **A guard keyed to a name protects the producer it was written against, not the property it
> describes.** The deferral now reads `if (r.get("quoted_by") or "").strip():` -- any named
> authority, because the field's meaning is "a ladder-level pass has already ruled here", and
> whether that pass was the collector is not the question the gate is asking.

**The figure converted the widened column into a different number.** `plot_paper.calib()` picked,
per message size, a quotable row over a non-quotable one and broke ties on lowest `T_us`. With one
quotable row per ladder that tiebreak never ran. With five it selected the fastest clean rung: the
pinned 18-lane variant's large-message efficiency read **0.1943** instead of **0.1796**, and the
selected rung moved in 8 of 16 ladders. That is the same 19.4-versus-17.96 error corrected once
already by hand -- returning this time as a property of the pipeline, which would have reproduced
it on every rebuild.

So the figure no longer trusts the column alone. Among quotable rows it takes the **lowest k** --
the first rung, which is what the rule names -- and prints a warning when a ladder offers more than
one, since under the rule it cannot. A consumer that can state the rule should enforce it rather
than infer it from an upstream flag.

Two smaller holes were closed alongside. The gate's link-rate check tested
`system.startswith("calib")`, and the consolidated calibration table has no `system` column at all,
so the proof-of-fixed-binary requirement was a no-op on precisely the rows it names; it now also
tests the file name. And 203 deferred rows carried `quotable=yes` with an empty `quotable_why` --
a verdict with no reason beside it -- which now records which pass ruled.

**How it was found.** Not by a check: by reading `git status` before staging and asking why a
committed calibration file was modified. The mechanical diff was 60 rows in one column; what made
it a defect was knowing that the rule is *first* clean rung and not *fastest*, which is a fact
about the method and not about the file. The gate is now idempotent over two full
build-then-gate cycles, and the regenerated table is byte-identical to the committed one in every
column it already had.

**Sub-class N is the one where the right answer was computed and thrown away.** The collector
knows exactly which configuration a rung belongs to -- `variant()` derives it from the tag, and the
walk grouping is keyed on it -- and the emitted row does not carry it. Downstream, `cliff_all.csv`
is assembled with a fixed key set that could not have carried it anyway, and R1 reduces each
`(system, ep)` to one point by preferring a quotable row and breaking ties on lowest makespan. Four
quotable rows arrived for glass at EP=32 and the tiebreak chose:

| walk | what it is | makespan |
|---|---|---|
| `sk1p2` | expert load skewed 1.2x | **74.814 ms — drawn** |
| `g32` | the plain configuration | 77.918 ms |
| `sk2p0` | expert load skewed 2.0x | 81.419 ms |
| `hier32` | hierarchical all-to-all | 202.683 ms |

> **A tiebreak is a selection rule wearing other clothes.** "Prefer quotable, then lowest makespan"
> reads as a tidy-up for duplicate rows. It is a rule that says: among things I cannot tell apart,
> report the most favourable. It was correct only for as long as the rows really were duplicates,
> and nothing anywhere asserted that they were.

The rung now records its walk key, `build_cliff_table.py` carries it, and R1 and the EP=128 panel
draw the plain configuration only -- announcing which cells they excluded, so the exclusion is
visible in the build log rather than implicit. Skew and hierarchical results are not lost; they are
their own claims, drawn where they belong, and the cliff figure no longer borrows them.

Two smaller corrections came out of the same pass. The first filter written for this was
`hier|sk\d|m\d+$`, and `m\d+$` matched `g16m8` -- which is not a microbatch variant but glass's
plain EP=16 walk, there being no separate `g16` -- so EP=16 fell back to a pre-fix portmap row at
86.750 in place of the post-fix 87.613. **A filter that removes the row it exists to keep is worse
than no filter**, and this one was caught only because the figure's own log named what it dropped.
And the tiebreak among quotable rows now sorts on ladder position rather than makespan: nvl64_pkt at
EP=16 had two clean rungs, q=544 at 130.797 and q=1088 at 130.295, and the rule names the first.
That one moves 0.4% against the fabric the paper advocates.

**A new instance of sub-class M, and the same lesson twice in one day.** `gate_quotable.py` walks
`experiments/results/paper/*.csv`. Five result files sit one directory up -- `edge_ep64.csv`,
`beyond64.csv`, `flat900_ep64.csv`, `flat_portcap.csv`, `nvl_latency_model.csv` -- all written
2026-09-06, the day before the link-rate fix landed at 10:01 on 09-07, none carrying
`link_rate_fixed`, and none reachable by any gate. `edge_ep64.csv` is named as R4's source in
`docs/figure_plan.md` and quoted in `docs/hierarchical_a2a_design.md` ("at EP=64 the 3200 edge
improves mean FCT 18% and P99 38% while the max FCT goes 91 -> 565 ms"). Its swept variable is the
cross-panel edge rate at 1600, 2400 and 3200 GB/s -- **every one of which truncated to zero
picoseconds per byte**, so the edge cost nothing at any of the three settings and the sweep varied
something that had no effect on transmission time. It is consistent with that reading that the
*faster* edge is the slower row throughout: qwenMoE 105.004 ms at 1600 against 2716.669 at 3200.
The figures do not read these files -- every panel loads from `results/paper/` -- so nothing drawn
is affected, and R4's glass EP=64 panel is now six post-fix rungs from `buffer_sweeps.csv`. The
exposure is in two design documents that cite a pre-fix artifact as evidence.

> **The scope of a check is part of the check.** M's first instance keyed a guard to a producer's
> name; this one keys it to a directory. Both protect exactly what was in front of the author.

**A third instance of the derived-table rule, in the sibling of the file already fixed for it.**
`build_cliff_table.py` runs the gate *before* it builds, then writes rows carrying whatever verdict
their source files hold -- so `python3 scripts/build_cliff_table.py` on its own left five pre-fix
glass EP=32 rows marked quotable at 75.52 ms, below the 77.918 the paper quotes, until some later
pass happened to demote them. `build_buffer_sweeps.py` was given its own pre-fix exclusion for
exactly this reason and its sibling was not, which is the second time these two files have been
fixed one at a time. It now demotes them itself, with a stated reason, rather than depending on
which script runs last.

**And an instance of sub-class H, still live in two writers.** `portcap_gate.sh` and
`flat900_ep64.sh` extract the port-cap banner with `awk '{print $1}'` from the line
`Flat port cap: ENABLED, one 50 GB/s egress port per node, ...`. The first field is `ENABLED,` --
the sentence's own comma -- pasted unquoted into a CSV. Every capped row in both files is one column
wide: `makespan_ps` empty, picoseconds under `makespan_ms`, milliseconds under `rtos`, the RTO count
under `wall_s`. The gate that checks the writer reads field 10 of the `gate_default` row, which is
the *uncapped* arm, whose banner has no comma; the self-check runs on the one arm the defect cannot
reach.

**Sub-class B has an instance in the inputs, not the outputs: the task graphs have no
producer either.** Every row in this paper is a simulation of one of four FlexFlow task
graphs -- `llamaMoE` at EP=16 and EP=32, `qwenMoE` at EP=64, `arctic` at EP=128 -- and
**no recorded command produces them.** Neither repository contains a script, a log, or a
note that generates a `*_paper_dp2tp1pp4_*` graph. The only generator script in the
FlexFlow tree, `profile_a100_test.sh`, builds a different model at a different
parallelism (`--train_dp 2 --train_tp 8 --train_pp 8`) and invokes a binary through
`./build_test/`, a directory that does not exist.

The gap surfaced from an ordinary request: an absolute pJ/token axis needs tokens per
iteration, which is global batch x sequence length. Each graph ships a `.meta` recording
dp, tp, pp, ep, topk, layers, seq, mb and devices -- and **not the batch size**. So the
token count is not derivable from the artifacts, and the obvious repair, re-running the
generator, is not available: the invocation would have to be reconstructed, and a
reconstructed graph that differs from the original says nothing about the original.

> **An input with no producer is the same defect as a figure with no producer, and it is
> further upstream.** Sub-class B was recorded for committed PNGs whose plotting scripts
> were in no repository. These are committed `.fbuf`s whose generation command is in no
> repository, and every measured row in the paper descends from them.

One number was recoverable and only one. A generator log survives for exactly one of the
seven graphs, and it states the batch size outright -- `attention batch size:128 ...
effective_num_elements:131072`, two independent numbers that agree at 128 x 1024. So
llamaMoE EP=32 has a sourced 131 072 tokens per iteration and the other six have none.

**The one guess that would have looked natural is already refuted by that log.** All
seven graphs are `dp2 tp1 pp4 seq1024`, differing only in model, `ep` and `topk`, so a
common batch size is plausible -- but the EP=32 graph runs on **256 devices with a batch
of 128**, so batch is not the device count, and filling EP=16 and EP=128 by that rule
would have been wrong in both directions while looking principled.

`tokens_per_iter.csv` therefore carries one sourced row and six blanks, each blank giving
its reason. Reading the count back out of the `.txt` graph dumps was tried and abandoned:
the dumps carry per-node byte counts rather than tensor shapes, the nodes are shards whose
size depends on the partitioning, and the four graphs do not yield to one rule -- the
first softmax node is 8 192 bytes at EP=16 and 16 777 216 at EP=32. Recovering tokens from
them would need assumptions about dtype, about which softmax is the router, and about
sharding, none of which are recorded either.

> **Every relative statement survives this; only the absolute axis does not.** Per-token
> is per-iteration divided by a constant per (model, EP), so ratios between fabrics,
> the microbatch shape and the energy comparison are all unaffected. That is the reason
> to state the gap and draw the panel at EP=32 rather than to fill six cells with a
> number that would be an assumption wearing an absolute unit.

**Sub-class G in someone else's simulator: two empty files from a run that reported
success.** The SimAI cross-check produced its numbers only after three false starts, and
all three have the same shape as the header-only `cliff_pkt.csv` — an artifact that
exists, is empty, and is indistinguishable from one that was never written.

- `ncclFlowModel_EndToEnd.csv`, the file SimAI names in its own stdout as the end-to-end
  result, is written **zero bytes** on a run that exits 0 and reports every node's bytes
  sent and received. Nothing says the summary was not produced.
- The ns-3 FCT file was **also** empty, for a different reason: the shipped
  `SimAI.conf` sets `MON_END 20000`, and every flow in an 8-GPU all-to-all completes
  after that, so the monitor discarded all 56 records. Widening the window is the only
  change to that file beyond the four monitor paths, which pointed at a root-owned
  `/etc/astra-sim` and made the binary segfault before any simulation — on the shipped
  example too, which is what proved it was environmental rather than ours.

The completion time therefore comes from the FCT records in the HPCC column convention,
as `max(start + fct) - min(start)` over the collective's flows, which is where our own
runs get theirs.

> **A results file that exists and is empty is the most expensive kind of missing.** It
> passes every check that asks whether the run succeeded, and only a check that asks
> what the file CONTAINS can see it.

**And the message-size convention was settled by a measurement rather than by reading
the collective source.** astra-sim's `ALLTOALL` takes one `comm_size` per layer and the
right value for M bytes per ordered pair is `8M`, not `7M` and not `M`: asking for
469 762 048 produced **56 flows — 8 GPUs x 7 peers, every ordered pair directly** — of
58 720 256 bytes each, and 8 x 58 720 256 is the request. Seven of eight chunks leave
each GPU. The check that this is right is the ladder's own asymptote: efficiency reaches
**0.9998** of line rate at 64 MB, where a factor-of-seven error would have landed at 0.14
or 7.0 and been unmissable. That was the plan before the first run, and it is why the
convention did not need a third opinion.

**What the cross-check licenses, and what it does not.** SimAI's NVSwitch is one
aggregate 450 GB/s link per GPU — the topology generator's only knob is `-nvbw` — so it
corresponds to our striped control and is silent on lane pinning, the effect the pinned
rows exist to quantify. Above 32 MB the two agree within 0.6% and above 8 MB within
3.5%. Below 2 MB they diverge by up to **142x**, because SimAI's stock model carries
essentially no small-message latency floor: it puts an 8 kB 8-GPU all-to-all at
**0.334 us**. Ours is 47.6-48.6 us against a published intra-node figure of ~45 us. So
the agreement is real at the ceiling and the disagreement at the floor is evidence for
this model rather than against it — which is the opposite of how a bare "cross-checked
against SimAI" would read.

**Sub-class O is the one where the check fails and the thing being checked is
fine.** Every sub-class above is a wrong number that looked right. This is the mirror:
a right artifact that a guard declared wrong, for a reason that has nothing to do with
what the guard measures.

`submit_batch10.sh` refuses to launch the panel DSE unless the run binary carries the
`GLASS_MAXDIST` gate — without it the mesh arm would silently be a second flattened
butterfly, so the check earns its place. It was written as

```sh
strings "$BIN" | grep -q GLASS_MAXDIST || { echo "REFUSING: ..."; exit 1; }
```

under the `set -uo pipefail` at the top of the script. `grep -q` exits at the first
match; `strings` is then killed by SIGPIPE; `pipefail` propagates its 141 as the
pipeline's status; and the script refuses **precisely when the string is present**. A
binary with no gate at all makes `grep` read to EOF and exit 1 with `strings` exiting
0 — no SIGPIPE, no failure — so the guard passes the case it exists to catch and
fails the case it exists to permit. It is inverted, not merely broken.

This is the same mechanism as the `head -8` that killed a python interpreter before it
could write `decomp_ops.csv`, and the fix is the same: **read the whole stream.**
`grep -c` with a numeric test costs one full scan of a 776 kB binary and cannot be
short-circuited.

> **A guard whose failure mode is a false refusal is not the safe direction.** It is
> tempting to treat "it only ever over-refuses" as harmless. It is not: for three
> hours the refusal was read as evidence about the *binary*, and the search went to
> the toolchain, the ODR violation and the protobuf ABI — every one of which was a
> real hazard, none of which was this. A check must be able to fail for exactly one
> reason or its output is not information.

Both copies were fixed — the launcher and the install script that stages the binary —
and the two verdicts they now print were confirmed against a binary known to carry the
gate and against the pre-rebuild binary known not to.

**Sub-class P is the citation that points at nothing.** Sub-class B was committed
artifacts whose producer is missing. This is its mirror in the other direction: a
producer that names its own source, in a docstring, for a source that does not exist.

`scripts/figures/plot_energy_final.py` opens with "All values documented in
`scripts/energy_methodology.md`". **There is no such file** — not under that name, not
under any other, anywhere in the repo or in the eight job snapshots that carry copies
of the script. The only occurrences of the string are the docstring itself and those
copies. Every energy constant the paper's headline figure rests on is therefore
asserted by a sentence that cannot be followed.

What that sentence was covering, established by reading the code rather than the claim:

| constant | what it is | what backs it |
|---|---|---|
| `NIC_PJ_BIT` 15.0 | scale-out NIC + switch port | **nothing** — see below |
| `NVS_STATIC_W_PER_GPU` (7.5, 12.5) | 540 W/rack / 72 GPUs, and 4x NVSwitch3 / 8 GPUs | reproduces the paper's published 39 / 62 GB/s/W exactly; no external source for the 540 W |
| `LASER_TUNE` 5.3 W/panel | 960 x 1 mW / 25% WPE + 2 x 960 x 0.75 mW | arithmetic only; no source for any of the three inputs |

The NIC figure is the one that had a live consequence. Its comment attributed 15.0 to
"the tier_power accounting" — and `scripts/tier_power.py` carries
`PJ_SCALEOUT = (16, 20)`, `scripts/whole_power2.py` carries `PJ_NIC = (16, 20)`, and
`docs/interconnect_parameters.md` documents the class as 16-20 pJ/bit. So the constant
was **below every documented figure in this repo**, and the accounting it named said
something else. It is now 16.0, the low end of the documented range, which is also the
conservative end because the figure is charged to the incumbent.

> **An attribution is not a citation until someone follows it.** Three constants each
> carried a phrase that reads like provenance — "per the tier_power accounting", "all
> values documented in ..." — and not one of the three survived being followed. The
> phrasing is what made them look settled; a bare number with no comment would have
> been questioned two months earlier.

The two that remain unsourced are not being repaired by invention. The NVSwitch pair is
labelled as the paper's own two system points, validated against its own published
numbers; the laser and ring-tuning inputs are labelled as budget assumptions. Both
statements are true and neither is a citation.

**Sub-class Q is the one there is no excuse for: a known defect, re-encountered.**
Every other entry here is something learned. This is something already written down in
this document and then walked into.

The Mixtral ablation was invalidated earlier the same day by an uncabled inter-panel
pair — `status=blocked`, `relayed_pairs=1`, uncabled pair **(12,14)**. That was
recorded. Batch 10's EP=128 arm was then submitted against `p64_ep128.txt` **without
checking that the map covers the traffic**, and all twelve jobs — both arms, six rungs
each — came back blocked on the same pair (12,14), after about five hours of compute
apiece. Nothing quotable was produced.

The map is not marginally short. The EP=128 workload uses **36 panel pairs; the map
cables 28**, and the eight it omits are

    (0,2) (1,3) (4,6) (5,7) (8,10) (9,11) (12,14) (13,15)

— every pair differing by two within groups of four, which is a systematic omission by
`gen_port_map.py` and not a random gap. Every cabled pair *is* used, so the map is a
strict subset of what the traffic needs. It is not a capacity limit either: only 15–16
of 64 ports per panel are in use. The map was generated with `used_pairs=None`, so it
laid down the generic `ep->[1] dp->[3] pp->[4]` pattern rather than cabling what the
workload actually exercises.

> **The check cost seconds and the omission cost twelve jobs.** Comparing the panel
> pairs a workload uses against the pairs a port map cables is one set difference over
> two files already on disk — no simulation, no binary. It was not run because the map
> had a plausible name and a header that looked authoritative.

Two consequences beyond the lost compute, both worse than the compute. **A blocked row
is not a slow row — it is a different fabric**, because a relayed flow did not use the
inter-panel link the topology claims to have. And one of those blocked EP=128 rungs
reads **19 934.507 ms**, a number which, had it reached a buffer-axis figure, would
have looked like a dramatic finding rather than an invalid run. `build_panel_dse.py`
now drops any row with `status != "sweep"` or `relayed_pairs > 0` and says on stderr
how many it dropped and at which EP, so the exclusion is loud rather than silent.

EP=128 is therefore **absent from the panel DSE by decision, not by omission**: it was
attempted, it was invalidated, and it is reported as attempted-and-invalidated. The
EP 16/32/64 arms are unaffected — they reported `relayed_pairs=0`, which is precisely
why they were quotable and these were not.

### Scope limit

This rule establishes that a parameter was *read*. It says nothing about whether
its value was *right*: instances 3 and 6 were both settings that the simulator
used exactly as given, and were wrong anyway because the value handed to it had
been derived under the wrong convention. Banners are necessary, not sufficient;
the derivation requirement in rule 3 is what covers the rest.
