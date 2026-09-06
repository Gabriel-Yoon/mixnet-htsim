#!/usr/bin/env python3
"""Which result rows are sensitive to the RTO floor?

The floor can only change a run that actually times out, so a row with rtos==0
is bit-identical at any floor and needs no re-run at 1 ms. Rows with rtos>0 are
the re-run set. Locates the rtos column by header name, since the CSVs do not
share a layout.

Caveat this deliberately does NOT paper over: floor-invariance is the only thing
rtos==0 buys. Such a row is still sensitive to buffer bytes and ECN_K, which the
transport sweep showed can move an inter=2000 run from 46.0 ms to 7.4 ms.
"""
import csv, glob, os, sys

RES = "experiments/results"
total_rows = total_hot = 0
report = []

for path in sorted(glob.glob(os.path.join(RES, "*.csv"))):
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    if not rows:
        continue
    hdr = rows[0]
    try:
        ri = hdr.index("rtos")
    except ValueError:
        report.append((path, None, 0, 0, []))
        continue
    hot = []
    n = 0
    for r in rows[1:]:
        if len(r) <= ri or not r[ri].strip():
            continue
        n += 1
        try:
            v = int(r[ri])
        except ValueError:
            continue
        if v > 0:
            hot.append((v, r))
    total_rows += n
    total_hot += len(hot)
    report.append((path, hdr, n, len(hot), sorted(hot, key=lambda x: -x[0])))

print("RTO-floor re-run triage  (rtos>0 => floor-sensitive => re-run at 1 ms)\n")
for path, hdr, n, nhot, hot in report:
    name = os.path.basename(path)
    if hdr is None:
        print(f"{name:<44} (no rtos column - skipped)")
        continue
    flag = "RE-RUN" if nhot else "clean"
    print(f"{name:<44} {nhot:>3}/{n:<4} rows hot   [{flag}]")
    for v, r in hot[:12]:
        print(f"      rtos={v:<6} {','.join(r)}")
    if len(hot) > 12:
        print(f"      ... and {len(hot)-12} more")

print(f"\nTOTAL: {total_hot} of {total_rows} rows are floor-sensitive "
      f"({100*total_hot/max(total_rows,1):.1f}%)")
print("Rows with rtos==0 are bit-identical at any floor and are NOT in the re-run set.")
print("They remain sensitive to buffer bytes and ECN_K, which this triage says nothing about.")
