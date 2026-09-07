#!/usr/bin/env python3
"""Consolidate the 96 calibration cells into calib_nvswitch.csv.

One row per rung, so the figure can draw the whole ladder and not just the quoted
point -- at small M the ladder is flat because the floor is latency-bound, and
that flatness is itself the match to the published ~45 us behaviour.

variant is written as s18 / s1 rather than a / b: the tags are terse but the table
is read by people. s18 is the paper's model (18 chip links, per-flow ECMP), s1 the
striped control. Both are 450 GB/s per GPU per direction.

quotable marks the first rung with no timeouts for each (variant, M) -- the same
vanishing-timeout rule as everywhere else. Efficiency is egress over 450 GB/s.

That verdict is a LADDER-level one and every row carries quoted_by=build_calib to
say so. Without the stamp the generic per-row gate cannot tell which rung came
first, marks every clean rung quotable, and the figure then draws the fastest --
19.43% where the rule says 17.96%.
"""
import csv, glob, os, re, sys

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
RUNGS = os.path.join(ROOT, "experiments/results/paper/rungs")
OUT = os.path.join(ROOT, "experiments/results/paper/calib_nvswitch.csv")

TAG = re.compile(r"^cal([ab])_M(\d+)_k(\d+)$")
VARIANT = {"a": "s18", "b": "s1"}

rows = []
for f in sorted(glob.glob(os.path.join(RUNGS, "cal*.csv"))):
    m = TAG.match(os.path.splitext(os.path.basename(f))[0])
    if not m:
        continue
    var, M, k = VARIANT[m.group(1)], int(m.group(2)), int(m.group(3))
    for r in csv.DictReader(open(f, newline="")):
        if (r.get("status") or "").strip() in ("submitted", "ABORTED", ""):
            continue
        if not (r.get("T_us") or "").strip():
            continue
        rows.append(dict(
            variant=var, msg_bytes=M, k=k, q=r.get("q_nvs"),
            q_over_bdp=r.get("q_over_bdp"), switches=r.get("switches"),
            link_gbps=r.get("link_gbps"), T_us=r.get("T_us"),
            egress_GBps=r.get("egress_GBps"), efficiency=r.get("efficiency"),
            rtos=r.get("rtos"), drops=r.get("drops"),
            makespan_ms=r.get("makespan_ms"), wall_s=r.get("wall_s"),
            link_rate_fixed=r.get("link_rate_fixed"), binary_sha=r.get("binary_sha"),
            quotable="no", quotable_why="not the first timeout-free rung",
            quoted_by="build_calib",
            note=r.get("note")))

# the vanishing-timeout rule, per (variant, M)
byladder = {}
for r in rows:
    byladder.setdefault((r["variant"], r["msg_bytes"]), []).append(r)
quoted = 0
for key, g in byladder.items():
    g.sort(key=lambda x: int(x["k"]))
    clean = [x for x in g if str(x.get("rtos", "")).strip() == "0"]
    if clean:
        clean[0]["quotable"] = "yes"
        clean[0]["quotable_why"] = "first timeout-free rung"
        quoted += 1

rows.sort(key=lambda r: (r["variant"], r["msg_bytes"], int(r["k"])))
fields = list(rows[0].keys())
with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=fields)
    w.writeheader(); w.writerows(rows)

print("wrote %s: %d rung(s), %d ladder(s) quoted" % (OUT, len(rows), quoted))
print()
print("  variant  M            T_us       egress      efficiency")
for r in rows:
    if r["quotable"] == "yes":
        print("   %-7s %-12s %-10s %-11s %s"
              % (r["variant"], r["msg_bytes"], r["T_us"], r["egress_GBps"], r["efficiency"]))
