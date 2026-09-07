#!/usr/bin/env python3
"""Repair the 200G/lane rows written by the frozen snapshot that predates two fixes.

The twelve 800 GB/s rungs were submitted against jobsnaps/batch5_20260907_163439,
whose rung.sh has `system=glassfb` as a literal (the RUNG_SYS knob was added two
lines above it and never wired to the place that reads it) and a caveat string
containing commas (csv_row does not quote, so the row shifted: the note's tail
landed in link_rate_fixed and binary_sha moved one place).

Both are fixed at the source, but a frozen snapshot is frozen on purpose -- the
running jobs keep the old script, which is the point of freezing it. So this
repairs their rows instead. Idempotent: re-run it as the remaining EP=128 rungs
land.

Nothing about the simulation is in question. The run banner recorded 800 GB/s per
port and the note recorded port_bw=800; only the columns after the comma were
mislabelled.
"""
import csv, glob, os

os.chdir("/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly")

NOTE_TAIL = "same 5.3 W/panel as 100G/lane and likely low for the higher-rate lanes; link pJ/bit unchanged (dynamic)"
repaired = 0
for p in sorted(glob.glob("experiments/results/paper/rungs/g*b800_q*.csv")):
    rows = list(csv.DictReader(open(p, newline="")))
    if not rows:
        continue
    fields = list(rows[0].keys())
    changed = False
    for r in rows:
        lrf = (r.get("link_rate_fixed") or "")
        if lrf.strip().startswith("same 5.3 W/panel"):
            # rejoin the note and shift the tail back one place
            r["note"] = (r.get("note") or "") + ", " + lrf.strip()
            r["link_rate_fixed"] = r.get("binary_sha") or ""
            r["binary_sha"] = r.get(None)[0] if r.get(None) else ""
            changed = True
        if (r.get("system") or "") == "glassfb" and "port_bw=800" in (r.get("note") or ""):
            r["system"] = "glassfb_800"
            changed = True
    if changed:
        with open(p, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
            w.writeheader(); w.writerows(rows)
        repaired += 1
print("repaired %d landed 800-rung file(s)" % repaired)
