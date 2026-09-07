#!/usr/bin/env python3
"""Apply the vanishing-timeout rule to every row, as a column, not as a label.

A row's `status` was set by whichever runner wrote it, and those gates predate
the rule. The EP=64 ground-truth row is the case: relay=0 and it completed, so
its script wrote `final` -- while carrying 102 601 timeouts, which the rule says
disqualifies it from being quoted.

Patching each runner's gate would not fix the rows already written, and several
runners are executing. So the rule is applied here, uniformly, as its own column:

    quotable=yes   relay-clean AND zero timeouts -- eligible as a headline row
    quotable=no    otherwise; the reason is given in quotable_why

`status` is left alone: it records what the run did, which is still true. This
column records whether the row may be quoted, which is a separate question.

Rows in a controlled comparison at a common buffer (the cabling 2x2) are marked
`grid` rather than `no`: they are not headline rows and were never meant to be,
and calling them unquotable would misdescribe them.
"""
import csv, glob, os

PAPER = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/paper"
GRID_FILES = {"dse_cabling_2x2.csv"}


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


for p in sorted(glob.glob(os.path.join(PAPER, "*.csv"))):
    name = os.path.basename(p)
    with open(p, newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows or "rtos" not in rows[0]:
        continue
    fields = list(rows[0].keys())
    for c in ("quotable", "quotable_why"):
        if c not in fields:
            fields.append(c)
    counts = {"yes": 0, "no": 0, "grid": 0, "?": 0}
    for r in rows:
        rt = num(r.get("rtos"))
        relay = num(r.get("relayed_pairs")) if "relayed_pairs" in r else 0
        ms = num(r.get("makespan_ms"))
        if name in GRID_FILES:
            r["quotable"], r["quotable_why"] = "grid", "controlled comparison at a common q; not a headline row"
        elif ms is None or ms == 0 or rt is None:
            r["quotable"], r["quotable_why"] = "no", "no completed iteration"
        elif relay and relay > 0:
            r["quotable"], r["quotable_why"] = "no", "relayed panel pair(s): %g" % relay
        elif rt > 0:
            r["quotable"], r["quotable_why"] = "no", "timeouts present: %g (vanishing-timeout rule)" % rt
        else:
            r["quotable"], r["quotable_why"] = "yes", "relay-clean and zero timeouts"
        counts[r["quotable"]] = counts.get(r["quotable"], 0) + 1
    with open(p, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader(); w.writerows(rows)
    print("  %-28s quotable: yes=%-3d no=%-3d grid=%-3d" % (name, counts["yes"], counts["no"], counts["grid"]))

print("\nheadline-eligible rows:")
for p in sorted(glob.glob(os.path.join(PAPER, "*.csv"))):
    with open(p, newline="") as fh:
        for r in csv.DictReader(fh):
            if r.get("quotable") == "yes":
                print("  %-26s %-10s ep=%-4s q=%-6s %10s ms" % (
                    os.path.basename(p), r.get("system") or r.get("cabling") or "",
                    r.get("ep", ""), r.get("q") or r.get("q_pkts") or r.get("q_nvs") or "",
                    r.get("makespan_ms", "")))
