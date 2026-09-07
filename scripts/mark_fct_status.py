#!/usr/bin/env python3
"""Mark every row's FCT columns clean or contaminated by an output-path collision.

The simulator names its output directory from a one-second timestamp, so two
runs of the same binary from the same working directory that start in the same
second append to one fct_util_out.txt. Their lines splice and every FCT-derived
column from that file is meaningless. makespan_ms and rtos come from each run's
own stdout log and are unaffected.

Sets fct_logdir (its own column: status_fct already records the payload/bracket
mode from fct_recompute.py and must not be overwritten) to:
    clean          the run's output directory was claimed by that run alone
    shared_logdir  the directory was claimed by 2+ runs; FCT columns are spliced
    (unchanged)    no run log could be matched to the row

Rows are matched to runs on makespan_ms, a measured quantity. Contaminated rows
are MARKED, not deleted: their makespan and RTO count are still good.
"""
import collections, csv, glob, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import csv_guard


ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
DC = os.path.join(ROOT, "src/clos/datacenter")
PAPER = os.path.join(ROOT, "experiments/results/paper")
RE_LD = re.compile(r"Log directory is:\s*(\S+)")
RE_IT = re.compile(r"finished one iter.*?now (\d+)")

claims = collections.defaultdict(list)      # logdir -> [runlog]
by_makespan = {}                            # "%.3f" -> logdir
for lg in sorted(glob.glob(os.path.join(DC, "*_logs", "*.log"))):
    ld, ps = None, None
    try:
        with open(lg, errors="replace") as fh:
            for line in fh:
                if ld is None:
                    m = RE_LD.search(line)
                    if m:
                        ld = m.group(1); continue
                if "finished one iter" in line:
                    m = RE_IT.search(line)
                    if m:
                        ps = int(m.group(1))
    except OSError:
        continue
    if ld:
        claims[ld].append(lg)
        if ps:
            by_makespan.setdefault("%.3f" % (ps / 1e9), ld)

shared = {d for d, v in claims.items() if len(v) > 1}
print("output directories: %d total, %d claimed by more than one run" % (len(claims), len(shared)))

for p in sorted(glob.glob(os.path.join(PAPER, "*.csv"))):

    why = csv_guard.skip_reason(p)
    if why:
        print("skip %s (%s)" % (os.path.basename(p), why)); continue
    before = csv_guard.stamp(p)
    with open(p, newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows or "makespan_ms" not in rows[0]:
        continue
    fields = list(rows[0].keys())
    if "fct_logdir" not in fields:
        anchor = fields.index("mean_fct_ms") if "mean_fct_ms" in fields else len(fields)
        fields.insert(anchor, "fct_logdir")
    n_clean = n_bad = n_unk = 0
    for r in rows:
        ld = by_makespan.get((r.get("makespan_ms") or "").strip())
        if ld is None:
            n_unk += 1
            continue
        if ld in shared:
            r["fct_logdir"] = "shared_logdir"; n_bad += 1
        else:
            r["fct_logdir"] = "clean"; n_clean += 1
    why = csv_guard.skip_reason(p, before)
    if why:
        print("skip %s (%s) -- not written" % (os.path.basename(p), why)); continue
    with open(p, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader(); w.writerows(rows)
    flag = "   <-- CONTAMINATED" if n_bad else ""
    print("  %-28s clean=%-4d shared_logdir=%-4d unmatched=%-4d%s"
          % (os.path.basename(p), n_clean, n_bad, n_unk, flag))
