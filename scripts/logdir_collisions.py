#!/usr/bin/env python3
"""Find runs that shared an output directory, and say which rows are affected.

The simulator names its output directory from a timestamp with one-second
resolution:

    oss << std::put_time(now_tm, "%m-%d-%H-%M-%S");
    logdir = "./logs/" + executableName + "_" + dateTime;

Two runs of the same binary from the same working directory that start in the
same second therefore share one fct_util_out.txt and append to it concurrently.
Their lines splice, and every FCT-derived column computed from that file is
meaningless -- the giveaway here was a max FCT of 5644288 ms, which is a flow
size in bytes.

makespan_ms and rtos are NOT affected: both come from the run's own stdout log,
which is per-cell.

This scans every run log for its claimed directory, reports each directory
claimed more than once, and maps the collision back to the makespan those cells
reported so the affected CSV rows can be marked.
"""
import collections, glob, os, re

DC = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter"
RE_LD = re.compile(r"Log directory is:\s*(\S+)")
RE_IT = re.compile(r"finished one iter.*?now (\d+)")

claims = collections.defaultdict(list)
for lg in sorted(glob.glob(os.path.join(DC, "*_logs", "*.log"))):
    ld, ps = None, None
    try:
        with open(lg, errors="replace") as fh:
            for line in fh:
                if ld is None:
                    m = RE_LD.search(line)
                    if m:
                        ld = m.group(1)
                        continue
                if "finished one iter" in line:
                    m = RE_IT.search(line)
                    if m:
                        ps = int(m.group(1))
    except OSError:
        continue
    if ld:
        claims[ld].append((os.path.relpath(lg, DC), "%.3f" % (ps / 1e9) if ps else "no-iteration"))

bad = {d: v for d, v in claims.items() if len(v) > 1}
print("scanned %d run logs, %d distinct output directories" % (
    sum(len(v) for v in claims.values()), len(claims)))
print("directories claimed by more than one run: %d\n" % len(bad))

affected = []
for d, runs in sorted(bad.items()):
    print("  %s" % d)
    for lg, ms in runs:
        print("      %-40s makespan %s ms" % (lg, ms))
        affected.append(ms)
    print()

if affected:
    print("CSV rows whose FCT columns are contaminated (match on makespan_ms):")
    for ms in sorted(set(affected)):
        if ms != "no-iteration":
            print("   ", ms)
    print("\nmakespan_ms and rtos in those rows remain valid -- only the FCT columns")
    print("and flow counts are spliced. Mark, do not delete.")
else:
    print("No collisions. Every run had its output directory to itself.")
