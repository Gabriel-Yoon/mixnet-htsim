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

# Canonical BDP per tier: link rate x that link's own round trip.
#   glass inter-panel port  400 GB/s x 2 x 500 ns = 400 000 B
#   NVLink port              50 GB/s x 4 x 250 ns =  50 000 B   (two hops each way)
#   NIC tier                 50-100 GB/s x 2000 ns rtt
BDP_BYTES = {"glassfb": 400000.0, "glassfb_hier": 400000.0,
             "nvl64_pkt": 50000.0, "hgx8_pkt": 112.5e9 * 1e-6,
             "nvl64": 100e9 * 2e-6, "hgx8": 50e9 * 2e-6}
MTU = 1500.0

# Family labels are not workload names. Several sweep CSVs carry model=pkt_glass
# with no model_name, which put a family label in the workload column of
# cliff_all before and does the same here if copied blindly.
FAMILY_LABELS = {"island", "pkt", "glass", "pkt_glass", "portmap", "mesh"}


def workload(r, default):
    for key in ("model_name", "model"):
        v = (r.get(key) or "").strip()
        if v and v not in FAMILY_LABELS:
            return v
    return default or ""


def qbdp(system, q):
    """q in MTU-sized packets against the tier's BDP, one convention everywhere.

    The source columns disagree: qfine_ep32.csv carries the old one-way-latency
    convention (2.0 / 3.75 for q about 1064) where the cliff rows say 4.0. The
    simulator's own NVSwitch banner uses a third value again -- it converts the
    queue to MSS-sized (1436 B) packets and then multiplies by 1500, so it reads
    15.6237 where q x MTU / BDP is 16.32, a 4.3% difference. This column is
    q x MTU / BDP for every row; the banner value is preserved separately so the
    discrepancy stays visible rather than being silently resolved.
    """
    b = BDP_BYTES.get(system)
    try:
        return "%.2f" % (float(q) * MTU / b) if b else ""
    except (TypeError, ValueError):
        return ""

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
    "cliff_ep64_tail.csv":       ("glassfb",   "qwenMoE",  64),
    "cliff_postfix.csv":         (None,        None,       None),
    "pkt_vanishing_timeout.csv": (None,        None,       None),
    "island_vanishing_timeout.csv": (None,     None,       None),
    # Re-runs with -logdir, so their FCT is this run's alone. They SUPERSEDE the
    # spliced originals for the same (system, ep, q) -- see the dedup below.
    "nvl64_ep16_clean.csv":      ("nvl64_pkt", "llamaMoE", 16),
}

RE_LOGDIR = re.compile(r"Log directory is:\s*(\S+)")
RE_ITER = re.compile(r"finished one iter.*?now (\d+)")


def index_runs():
    """makespan -> fct path, plus the set of makespans whose output directory was
    claimed by more than one run.

    The simulator names its output directory from a one-second timestamp, so two
    concurrent runs can share one fct_util_out.txt and splice each other's lines.
    A spliced file yields nonsense that still parses: the glass EP=32 q=1000 row
    carried a max FCT of 5644288 ms, which is a flow size in bytes. The plotter
    should never have to know that, so such values are blanked here and the
    reason recorded in fct_status.
    """
    idx = {}
    claims = collections.defaultdict(list)
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
            key = "%.3f" % (ps / 1e9)
            idx.setdefault(key, os.path.join(base, "fct_util_out.txt"))
            claims[ld].append(key)
    shared = set()
    for ld, keys in claims.items():
        if len(keys) > 1:
            shared.update(keys)
    return idx, shared


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


(idx, shared_dirs), drops = index_runs(), load_drops()
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
        # FCT provenance: a value from a shared output directory is spliced and
        # must not reach the plotter, whether it was copied from the source row
        # or computed here.
        # A row's own fct_status wins over the makespan-based inference. The
        # inference keys on makespan, and this simulator is deterministic: a
        # clean re-run reproduces the spliced original's makespan exactly, so
        # the index cannot tell them apart and would mark the re-run collided.
        # The re-run knows it wrote its own -logdir; believe it.
        fct_status = (r.get("fct_status") or r.get("fct_logdir") or "").strip()
        if not fct_status:
            fct_status = "shared_logdir" if ms in shared_dirs else (
                "clean" if ms in idx else "no_run_log")
        mx = pick(r, "max_fct_ms")
        if fct_status != "clean":
            mx = ""
        elif not mx and ms in idx:
            mx = payload_max(idx[ms]); filled += 1 if mx else 0
        rows.append(dict(
            system=sysname, ep=ep, model_name=workload(r, dmodel),
            q=q, q_over_bdp=qbdp(sysname, q),
            q_over_bdp_source=pick(r, "q_over_bdp", "q_over_bdp_banner", "q_over_bdp_4lat"),
            makespan_ms=ms, rtos=pick(r, "rtos"),
            # A row's own drops win over the quoted_row_drops join, for the same
            # reason its fct_status does: the sweep re-runs measured their own.
            drops=((r.get("drops") or "").strip() or drops.get((sysname, ep, q), "")),
            max_fct_ms=mx,
            fct_status=fct_status, quotable=pick(r, "quotable"),
            # Carried, not recomputed. Without these the gate cannot tell a post-fix
            # row from a pre-fix one, and R4's "lowest makespan per step" rule then
            # draws the pre-fix number -- 39.395 instead of 43.088 at glass EP=64.
            link_rate_fixed=pick(r, "link_rate_fixed"),
            binary_sha=pick(r, "binary_sha"),
            quoted_by=pick(r, "quoted_by"),
            source=name))


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


# Where a cell was re-run on a clean log, drop the spliced original: same
# (system, ep, q), and the re-run reproduced the original makespan exactly, so
# they are the same measurement with and without a usable FCT file.
clean_keys = {(r["system"], r["ep"], r["q"]) for r in rows
              if r["source"] == "nvl64_ep16_clean.csv"}
before = len(rows)
rows = [r for r in rows
        if not ((r["system"], r["ep"], r["q"]) in clean_keys
                and r["source"] != "nvl64_ep16_clean.csv")]
if before != len(rows):
    print("superseded %d spliced row(s) with clean re-runs" % (before - len(rows)))

# One point per (system, ep, q, makespan). The same measurement can reach this
# table from two files: cliff_ep64_gt_ext.csv holds the walk's rows and
# cliff_ep64_tail.csv the re-run that measured their tails, and both describe
# q=8533 and q=17067 at 39.410 and 39.395 ms. R4 would then plot each point
# twice.
#
# Keep the row that carries a tail, and among those the one whose OWN run
# measured it. The walk's rows only have a tail because this builder matched
# their makespan to the re-run's output directory -- sound, since the configs are
# identical and the model is deterministic, but it is an inference, and where a
# row measured the thing itself that row should win.
#
# The makespan is part of the key, so two genuinely different measurements at the
# same buffer stay as two points rather than being silently collapsed.
_TAIL_OWNERS = ("cliff_ep64_tail.csv",)
_seen = {}
for r in rows:
    k = (r["system"], r["ep"], r["q"], r["makespan_ms"])
    prev = _seen.get(k)
    if prev is None:
        _seen[k] = r
        continue
    def _rank(x):
        return (x["source"] in _TAIL_OWNERS, bool(x["max_fct_ms"]))
    if _rank(r) > _rank(prev):
        _seen[k] = r
_dropped = len(rows) - len(_seen)
rows = list(_seen.values())
if _dropped:
    print("collapsed %d duplicate sweep point(s) reaching the table from two files"
          % _dropped, file=sys.stderr)

# Drop pre-fix rungs of the affected fabrics. Stated here rather than left to
# gate_quotable, because this table is rebuilt by a pipeline whose step order has
# already made one derived table disagree with its own source today.
_AFFECTED = ("glassfb", "hgx8_pkt", "nvl64_pkt_s1")
_before = len(rows)
rows = [r for r in rows
        if not (str(r.get("system", "")).startswith(_AFFECTED)
                and (r.get("link_rate_fixed") or "").strip().lower() != "yes")]
_dropped = _before - len(rows)
if _dropped:
    print("dropped %d pre-fix rung(s) of glassfb/hgx8_pkt/nvl64_pkt_s1; "
          "nvl64_pkt (L=50, always exact) kept" % _dropped, file=sys.stderr)

rows.sort(key=lambda r: (r["system"], num(r["ep"]), num(r["q"])))
with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["system", "ep", "model_name", "q", "q_over_bdp",
                                       "q_over_bdp_source", "makespan_ms", "rtos", "drops",
                                       "max_fct_ms", "fct_status", "quotable",
                                       "link_rate_fixed", "binary_sha", "quoted_by",
                                       "source"])
    w.writeheader(); w.writerows(rows)

blanked = sum(1 for r in rows if r["fct_status"] != "clean")
print("wrote %s: %d sweep points (%d max-FCT read from run logs, %d blanked as not clean)"
      % (OUT, len(rows), filled, blanked))
by = collections.Counter((r["system"], r["ep"]) for r in rows)
for (s, e), n in sorted(by.items()):
    print("  %-12s ep=%-4s %d point(s)" % (s, e, n))
