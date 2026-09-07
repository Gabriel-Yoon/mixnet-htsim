#!/usr/bin/env python3
"""Re-derive the FCT columns, separating the single-packet population.

WHY, AND WHY NOT THE OBVIOUS WAY. 64 of the 128 all-to-all tasks in these traces
carry xfersize 0 (the GROUP_BY pair; AGGREGATE carries 268435456), and the flat
all-to-all launches one flow per pair for them -- 15 744 zero-byte flows per
EP=16 run. The natural fix is to drop FCT records with flowsize 0.

That fix does nothing, and measuring it says so: 0.0% of FCT records have size 0
in every run. tcp.cpp:161 floors the size --

    if (_flow_size < _mss)
        _flow_size = _mss;

-- so a zero-byte flow is not skipped. It opens a connection, sends one 1436-byte
packet and writes a normal FCT record. The FCT log's minimum size is 1436, never 0.

So the contaminating population is the flows that carry exactly one MSS. It is
NOT exactly the zero-byte population: at EP=16 there are 21 120 one-MSS records
against 15 744 zero-byte flows, so ~5 400 are genuine sub-MSS flows being
excluded with them. The one-MSS count is therefore an UPPER BOUND on the
zero-origin flows, and the ">1 MSS" triples are a slight over-correction. Both
populations are reported rather than picking one and calling it the answer.

Exact separation needs the requested size, which only the sender knows; that is
a code change (log the pre-floor size in the FCT record), not something
recoverable from the runs already done.

WHAT THIS DOES NOT EXPLAIN. p50 is 0.0008 ms with the one-MSS flows in AND with
them out. The median is small because the workload's flows are small: at EP=16,
31 744 records are 8194 B and 21 120 are 1436 B, so 67% are <= 8 KB. p50 is not
an artifact and should not be reported as one.

Columns:
  flows_total       every FCT record
  flows_one_mss     records at exactly one MSS (upper bound on zero-origin)
  flows_payload     records above one MSS
  mean/p50/p99/max_fct_ms        over flows_payload
  mean/p50/p99/max_fct_ms_all    over every record (what was published before)

The old `flows` column is renamed flows_a2a_only: it came from
`grep -c 'flow_size:'`, the single all-to-all print site, so it counts all-to-all
flows alone and is not a total.

Percentiles are nearest-rank on the ascending sort, 1-based: value at index
ceil(f*n). The previous awk used int(n*0.99), a different convention.

Rows join to runs on makespan_ms, a measured quantity, not on file position. An
unmatched row keeps its original values and is marked UNMATCHED.
"""
import csv, math, os, re, sys, glob

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
DC = os.path.join(ROOT, "src/clos/datacenter")
PAPER = os.path.join(ROOT, "experiments/results/paper")

RE_LOGDIR = re.compile(r"Log directory is:\s*(\S+)")
RE_ITER = re.compile(r"finished one iter.*?now (\d+)")


def scan_runs():
    idx = {}
    for lg in glob.glob(os.path.join(DC, "*_logs", "*.log")):
        logdir, last_ps = None, None
        try:
            with open(lg, "r", errors="replace") as fh:
                for line in fh:
                    if logdir is None:
                        m = RE_LOGDIR.search(line)
                        if m:
                            logdir = m.group(1)
                            continue
                    if "finished one iter" in line:
                        m = RE_ITER.search(line)
                        if m:
                            last_ps = int(m.group(1))
        except OSError:
            continue
        if not logdir or not last_ps:
            continue
        base = logdir if os.path.isabs(logdir) else os.path.join(DC, logdir.lstrip("./"))
        idx.setdefault("%.3f" % (last_ps / 1e9), []).append(os.path.join(base, "fct_util_out.txt"))
    return idx


def pct(vals, f):
    n = len(vals)
    return vals[min(n - 1, max(0, math.ceil(f * n) - 1))]


def stats(path, mss=1436):
    allv, payv, one = [], [], 0
    exact = [False]
    try:
        with open(path, "r", errors="replace") as fh:
            for line in fh:
                if not line.startswith("FCT "):
                    continue
                f = line.split()
                if len(f) < 5:
                    continue
                sz, fct = float(f[3]), float(f[4])
                allv.append(fct)
                # Column 7, when the run's binary writes it, is the size the caller
                # asked for before the one-MSS floor -- an exact split instead of
                # the bracket. Older runs have 6 columns and fall back.
                if len(f) >= 7:
                    exact[0] = True
                    trivial = float(f[6]) <= 0
                else:
                    trivial = sz <= mss
                if trivial:
                    one += 1
                else:
                    payv.append(fct)
    except OSError:
        return None
    if not allv:
        return None
    allv.sort(); payv.sort()
    d = dict(total=len(allv), one_mss=one, payload=len(payv),
             mode="requested_size" if exact[0] else "one_mss_bracket")
    for tag, v in (("all", allv), ("pay", payv)):
        if v:
            d[tag] = dict(mean=sum(v) / len(v), p50=pct(v, .50), p99=pct(v, .99), mx=v[-1])
        else:
            d[tag] = dict(mean="", p50="", p99="", mx="")
    return d


def fmt(v):
    return "" if v == "" else "%.4f" % v


def main():
    idx = scan_runs()
    print("indexed %d distinct makespans from run logs\n" % len(idx))
    NEW = ["flows_total", "flows_one_mss", "flows_payload", "p50_fct_ms",
           "mean_fct_ms_all", "p50_fct_ms_all", "p99_fct_ms_all", "max_fct_ms_all",
           "status_fct"]

    for csvpath in sorted(glob.glob(os.path.join(PAPER, "*.csv"))):
        with open(csvpath, newline="") as fh:
            rows = list(csv.DictReader(fh))
        if not rows or "makespan_ms" not in rows[0]:
            print("skip %s (no makespan_ms)" % os.path.basename(csvpath)); continue

        fields = list(rows[0].keys())
        if "flows" in fields:
            fields[fields.index("flows")] = "flows_a2a_only"
            for r in rows:
                r["flows_a2a_only"] = r.pop("flows")
        anchor = fields.index("mean_fct_ms") if "mean_fct_ms" in fields else len(fields)
        for i, c in enumerate(NEW):
            if c not in fields:
                fields.insert(anchor + i, c)

        print("=== %s ===" % os.path.basename(csvpath))
        nm = 0
        for r in rows:
            key = r.get("makespan_ms", "").strip()
            st = None
            for fct in idx.get(key, []):
                st = stats(fct)
                if st:
                    break
            if not st:
                r["status_fct"] = "UNMATCHED"
                for c in NEW[:-1]:
                    r.setdefault(c, "")
                print("  makespan=%-11s UNMATCHED -- left as-is" % key)
                continue
            nm += 1
            om, op = r.get("mean_fct_ms", ""), r.get("p99_fct_ms", "")
            r["flows_total"] = st["total"]
            r["flows_one_mss"] = st["one_mss"]
            r["flows_payload"] = st["payload"]
            r["mean_fct_ms_all"] = fmt(st["all"]["mean"]); r["p50_fct_ms_all"] = fmt(st["all"]["p50"])
            r["p99_fct_ms_all"] = fmt(st["all"]["p99"]);  r["max_fct_ms_all"] = fmt(st["all"]["mx"])
            r["mean_fct_ms"] = fmt(st["pay"]["mean"]);    r["p50_fct_ms"] = fmt(st["pay"]["p50"])
            r["p99_fct_ms"] = fmt(st["pay"]["p99"]);      r["max_fct_ms"] = fmt(st["pay"]["mx"])
            r["status_fct"] = st["mode"]
            print("  makespan=%-11s total=%-7d one-MSS=%-6d (%4.1f%%)  mean %s -> %s   p99 %s -> %s   p50(all)=%s p50(pay)=%s"
                  % (key, st["total"], st["one_mss"], 100.0 * st["one_mss"] / st["total"],
                     om or "-", r["mean_fct_ms"] or "-", op or "-", r["p99_fct_ms"] or "-",
                     r["p50_fct_ms_all"], r["p50_fct_ms"]))

        with open(csvpath, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            for r in rows:
                w.writerow(r)
        print("  -> %d/%d rows re-derived\n" % (nm, len(rows)))


if __name__ == "__main__":
    main()
