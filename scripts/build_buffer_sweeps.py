#!/usr/bin/env python3
"""One file for R4: makespan and tail against buffer, on both fabrics.

The buffer sweeps live in seven CSVs that grew separately and disagree about
column names -- the buffer is `q`, `q_pkts` or `q_nvs`; the multiple is
`q_over_bdp`, `q_over_bdp_banner` or `q_over_bdp_4lat`; only some carry a max
FCT. Hand-concatenating them is how the 36-vs-46 column shift happened, so this
normalises them the same way cliff_all does: gate first, then table, nothing
recomputed that a row already measured.

max_fct_ms is taken from the row where it exists and otherwise read from that
run's own FCT log, matched on makespan -- a measured quantity, not file order.
It is the PAYLOAD max (flows above one MSS), consistent with the FCT columns
elsewhere: the zero-byte all-to-all flows are floored to one packet and would
otherwise crowd the tail with records that moved nothing.

drops come from quoted_row_drops.csv where measured; blank where not, never
assumed zero.
"""
import collections, csv, glob, os, re, runpy, sys

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
PAPER = os.path.join(ROOT, "experiments/results/paper")
DC = os.path.join(ROOT, "src/clos/datacenter")
OUT = os.path.join(PAPER, "buffer_sweeps.csv")

# gate first, so `quotable` is current before the table is built
try:
    runpy.run_path(os.path.join(ROOT, "scripts/gate_quotable.py"), run_name="__gated__")
except Exception as e:
    print("WARNING: gate_quotable did not run (%s); quotable may be stale" % e, file=sys.stderr)

SOURCES = {
    "nvl64_ksweep.csv":          ("nvl64_pkt", "llamaMoE", 16),
    "nvl64_ksweep_hi.csv":       ("nvl64_pkt", "llamaMoE", 16),
    "nvl64_outlier.csv":         ("nvl64_pkt", "llamaMoE", 16),
    "cliff_ep32_gt_ksweep.csv":  ("glassfb",   "llamaMoE", 32),
    "qfine_ep32.csv":            ("glassfb",   "llamaMoE", 32),
    "qplateau_ep32.csv":         ("glassfb",   "llamaMoE", 32),
    "cliff_ep64_gt.csv":         ("glassfb",   "qwenMoE",  64),
    "cliff_ep64_gt_ext.csv":     ("glassfb",   "qwenMoE",  64),
    "pkt_vanishing_timeout.csv": (None,        None,       None),
    "island_vanishing_timeout.csv": (None,     None,       None),
}

RE_LOGDIR = re.compile(r"Log directory is:\s*(\S+)")
RE_ITER = re.compile(r"finished one iter.*?now (\d+)")


def index_runs():
    idx = {}
    for lg in glob.glob(os.path.join(DC, "*_logs", "*.log")):
        ld = ps = None
        try:
            with open(lg, errors="replace") as fh:
                for line in fh:
                    if ld is None:
                        m = RE_LOGDIR.search(line)
                        if m:
                            ld = m.group(1); continue
                    if "finished one iter" in line:
                        m = RE_ITER.search(line)
                        if m:
                            ps = int(m.group(1))
        except OSError:
            continue
        if ld and ps:
            base = ld if os.path.isabs(ld) else os.path.join(DC, ld.lstrip("./"))
            idx.setdefault("%.3f" % (ps / 1e9), os.path.join(base, "fct_util_out.txt"))
    return idx


def payload_max(path, mss=1436):
    try:
        m = 0.0
        with open(path, errors="replace") as fh:
            for line in fh:
                if not line.startswith("FCT "):
                    continue
                f = line.split()
                if len(f) >= 5 and float(f[3]) > mss:
                    v = float(f[4])
                    if v > m:
                        m = v
        return "%.4f" % m if m else ""
    except OSError:
        return ""


def load_drops():
    p = os.path.join(PAPER, "quoted_row_drops.csv")
    d = {}
    if os.path.exists(p):
        for r in csv.DictReader(open(p, newline="")):
            v = (r.get("drops") or "").strip()
            if v.isdigit():
                d[(r.get("system", ""), (r.get("ep") or "").strip(), (r.get("q") or "").strip())] = v
    return d


def pick(r, *names):
    for n in names:
        v = r.get(n)
        if v not in (None, ""):
            return v
    return ""


idx, drops = index_runs(), load_drops()
rows, filled = [], 0
for name, (dsys, dmodel, dep) in SOURCES.items():
    p = os.path.join(PAPER, name)
    if not os.path.exists(p):
        continue
    for r in csv.DictReader(open(p, newline="")):
        ms = pick(r, "makespan_ms")
        if ms in ("", "0.000", "0"):
            continue                      # no completed iteration: not a sweep point
        sysname = pick(r, "system") or dsys or ""
        q = pick(r, "q", "q_pkts", "q_nvs")
        ep = pick(r, "ep") or (str(dep) if dep else "")
        mx = pick(r, "max_fct_ms")
        if not mx and ms in idx:
            mx = payload_max(idx[ms]); filled += 1 if mx else 0
        rows.append(dict(
            system=sysname, ep=ep, model_name=pick(r, "model_name", "model") or dmodel or "",
            q=q, q_over_bdp=pick(r, "q_over_bdp", "q_over_bdp_banner", "q_over_bdp_4lat"),
            makespan_ms=ms, rtos=pick(r, "rtos"),
            drops=drops.get((sysname, ep, q), ""), max_fct_ms=mx,
            quotable=pick(r, "quotable"), source=name))


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


rows.sort(key=lambda r: (r["system"], num(r["ep"]), num(r["q"])))
with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["system", "ep", "model_name", "q", "q_over_bdp",
                                       "makespan_ms", "rtos", "drops", "max_fct_ms",
                                       "quotable", "source"])
    w.writeheader(); w.writerows(rows)

print("wrote %s: %d sweep points (%d max-FCT values read from run logs)" % (OUT, len(rows), filled))
by = collections.Counter((r["system"], r["ep"]) for r in rows)
for (s, e), n in sorted(by.items()):
    print("  %-12s ep=%-4s %d point(s)" % (s, e, n))
