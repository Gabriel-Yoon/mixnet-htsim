#!/usr/bin/env python3
"""One table for the cliff figure, so nobody has to concatenate five schemas.

The cliff rows live in files that grew separately and do not share a schema:
cliff.csv calls the workload `model_name` and the family `model`; cliff_pkt.csv
uses `model_name` with `model`=pkt; the glass files use `cabling` and have no
`system` at all in one case; the buffer column is `q`, `q_pkts` or `q_nvs`
depending on the file. Concatenating them by hand is how the 36-vs-46 column
shift happened.

This emits experiments/results/paper/cliff_all.csv with ONE schema, carrying the
`quotable` flag through so the figure can filter on it rather than on a status
word that means different things in different files. Nothing is recomputed here:
every value is copied from the row that measured it, and `source` names the file
it came from so any number can be traced back in one step.

Rows that are not quotable are kept, not dropped -- the sweeps are the evidence
that the quoted point is the right one, and a figure that wants only headline
rows can filter `quotable == yes`.
"""
import csv, glob, os, runpy, sys

# Apply the vanishing-timeout rule BEFORE reading. The sweep scripts write their
# own `quoted` column; the `quotable` column this table carries is applied by
# gate_quotable.py afterwards. Running them in the wrong order silently produced
# a table missing the quotable NVL-64 EP=32 row -- the file was among the inputs,
# the flag simply had not been computed for it yet. A two-step pipeline whose
# steps must be run in order is a trap; this removes the order from the caller.
_HERE = os.path.dirname(os.path.abspath(__file__))
try:
    runpy.run_path(os.path.join(_HERE, "gate_quotable.py"), run_name="__gated__")
except Exception as e:                      # never let the gate stop the table
    print("WARNING: gate_quotable.py did not run (%s); `quotable` may be stale" % e,
          file=sys.stderr)

PAPER = os.environ.get("PAPER_RES", "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/paper")
OUT = os.path.join(PAPER, "cliff_all.csv")

# `variant` is the collector's configuration key -- g32 / sk1p2 / sk2p0 / hier32 all
# share (system, ep, mb) and are different experiments. Dropping it made every
# consumer downstream unable to tell them apart, and R1 drew whichever was fastest.
FIELDS = ["paper_ref", "family", "system", "variant", "walk", "model_name", "topk", "ep", "mb", "nodes",
          "q", "q_over_bdp", "rto_min_us", "mtu", "makespan_ms", "rtos",
          "quotable", "quotable_why", "fct_logdir", "source", "note",
          "link_rate_fixed", "quoted_by"]

# file -> (system when the file has no `system` column, workload when it has no
# usable `model_name`). Family labels are NOT workload names: several glass files
# carry model=pkt_glass and no model_name, which leaked into the workload column.
SOURCES = {
    "cliff.csv":                (None,      None),
    "cliff_pkt.csv":            (None,      None),
    "cliff_pkt_ep128.csv":      (None,      None),
    "cliff_pkt_stripe.csv":     (None,      None),
    # post-fix rungs, one job per rung, quoted by collect_rungs.py which is the
    # only component that sees a whole walk. system and model come from the rows.
    "cliff_postfix.csv":        (None,      None),   # post-fix rungs; quoted by collect_rungs.py,
                                                 # which is the only component that sees a whole walk
    "cliff_ep32_gt.csv":        ("glassfb", "llamaMoE"),
    "cliff_ep32_gt_ksweep.csv": ("glassfb", "llamaMoE"),
    "cliff_ep64_gt.csv":        ("glassfb", "qwenMoE"),
    "cliff_ep64_gt_ext.csv":    ("glassfb", "qwenMoE"),   # 16x/32x/64x walk rungs incl. the quoted 64x row
    "cliff_portmap.csv":        ("glassfb", None),
    "mb_sweep.csv":             (None,      "llamaMoE"),
    "pkt_vanishing_timeout.csv":(None,      None),
    "qplateau_ep32.csv":        ("glassfb", "llamaMoE"),
    "qfine_ep32.csv":           ("glassfb", "llamaMoE"),
    # the EP=16 packet-level headline points live here; without them the figure
    # has no quotable NVL-64 EP=16 row at all
    "nvl64_ksweep_hi.csv":      ("nvl64_pkt", "llamaMoE"),
    "nvl64_ksweep.csv":         ("nvl64_pkt", "llamaMoE"),
    "nvl64_outlier.csv":        ("nvl64_pkt", "llamaMoE"),
    "cliff_buffer_sensitivity.csv": (None,   None),
}

FAMILY_LABELS = {"island", "pkt", "glass", "pkt_glass", "portmap", "mesh"}


def pick(r, *names):
    for n in names:
        v = r.get(n)
        if v not in (None, ""):
            return v
    return ""


def family_of(system, r):
    # The SYSTEM name is checked first and wins. mb_sweep.sh writes model=pkt on
    # every row including its glassfb cells, so the model column is not reliable
    # where the two disagree; the system name is what the run actually was.
    s = (system or "").lower()
    if s.startswith("glass"):
        return "glass"
    if s.endswith("_pkt"):
        return "pkt"
    if s in ("nvl64", "hgx8"):
        return "island"
    m = (r.get("model") or "").strip()
    if m in ("island", "pkt", "glass", "pkt_glass"):
        return "glass" if m == "pkt_glass" else m
    return m or ""


def workload_of(r, default_model):
    """The workload, never a family label. cliff_ep32_gt_ksweep.csv and friends
    carry model=pkt_glass with no model_name; taking that as the workload put a
    family label in the workload column."""
    v = pick(r, "model_name")
    if v and v not in FAMILY_LABELS:
        return v
    v = pick(r, "model")
    if v and v not in FAMILY_LABELS:
        return v
    return default_model or ""


out = []
for name, (default_system, default_model) in SOURCES.items():
    p = os.path.join(PAPER, name)
    if not os.path.exists(p):
        continue
    with open(p, newline="") as fh:
        for r in csv.DictReader(fh):
            ms = pick(r, "makespan_ms")
            if ms in ("", "0.000", "0"):
                continue                     # no completed iteration; not a figure row
            system = pick(r, "system") or default_system or ""
            out.append({
                "paper_ref": pick(r, "paper_ref"),
                "family": family_of(system, r),
                "system": system,
                "model_name": workload_of(r, default_model),
                "topk": pick(r, "topk"),
                "ep": pick(r, "ep"),
                "mb": pick(r, "mb"),
                "nodes": pick(r, "nodes"),
                "q": pick(r, "q", "q_pkts", "q_nvs"),
                "q_over_bdp": pick(r, "q_over_bdp", "q_over_bdp_banner", "q_over_bdp_4lat"),
                "rto_min_us": pick(r, "rto_min_us"),
                "mtu": pick(r, "mtu"),
                "makespan_ms": ms,
                "rtos": pick(r, "rtos"),
                "variant": pick(r, "variant"),
                "walk": pick(r, "walk"),
                "quotable": pick(r, "quotable"),
                "quotable_why": pick(r, "quotable_why"),
                "fct_logdir": pick(r, "fct_logdir"),
                "source": name,
                "note": pick(r, "note"),
                # Carried, not recomputed. gate_quotable runs again over this table
                # (build_buffer_sweeps invokes it), and without these it cannot tell
                # a post-fix row from a pre-fix one and demotes every one of them.
                "link_rate_fixed": pick(r, "link_rate_fixed"),
                "quoted_by": pick(r, "quoted_by"),
            })

def _n(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


# Drop pre-fix rungs of the affected fabrics here, not in whichever gate pass
# happens to run last. build_cliff_table invokes the gate BEFORE it builds, so a
# `python3 scripts/build_cliff_table.py` on its own left five pre-fix glass EP=32
# rows marked quotable -- 75.52 ms from a binary whose electrical tier had no
# transmission time, sitting below the 77.918 the paper quotes.
#
# Dropped rather than demoted. Demoting kept them drawable as hollow sensitivity
# points, and for an AFFECTED fabric a pre-fix row is not a sensitivity point: it
# is an artifact. 48 survived that way, and glass EP=64's pre-fix 39.395 and
# 39.410 sit BELOW the post-fix quoted 43.088, where a hollow marker reads as
# "glass does better at some other buffer". build_buffer_sweeps drops them; this
# is the same rule in its sibling.
#
# The cost is one point: hgx8_pkt EP=128, whose only row is the pre-fix 365.733.
# Batch 4 is measuring it, and a gap that fills when the job lands is better than
# a number from a binary whose NVLink tier ran 11% fast.
_AFFECTED = ("glassfb", "hgx8_pkt", "nvl64_pkt_s1")
_before = len(out)
_gone = sorted({(r["system"], r["ep"]) for r in out
                if str(r.get("system", "")).startswith(_AFFECTED)
                and (r.get("link_rate_fixed") or "").strip().lower() != "yes"})
out = [r for r in out
       if not (str(r.get("system", "")).startswith(_AFFECTED)
               and (r.get("link_rate_fixed") or "").strip().lower() != "yes")]
_dropped = _before - len(out)
_left = {(r["system"], r["ep"]) for r in out}
if _dropped:
    print("dropped %d pre-fix rung(s) of glassfb/hgx8_pkt/nvl64_pkt_s1; "
          "nvl64_pkt (L=50, always exact) kept" % _dropped, file=sys.stderr)
    for k in _gone:
        if k not in _left:
            print("  NOTE: %s ep=%s now has NO row at all -- its only measurement was "
                  "pre-fix" % k, file=sys.stderr)

out.sort(key=lambda r: (r["family"], r["system"], _n(r["ep"]), _n(r["mb"]), _n(r["makespan_ms"])))
with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=FIELDS)
    w.writeheader(); w.writerows(out)

q = [r for r in out if r["quotable"] == "yes"]
print("wrote %s: %d rows, %d quotable\n" % (OUT, len(out), len(q)))
print("quotable rows (the cliff figure):")
for r in sorted(q, key=lambda r: (r["ep"], r["family"], r["system"])):
    print("  ep=%-4s mb=%-3s %-10s %-12s q=%-6s %10s ms  (%s)" % (
        r["ep"], r["mb"] or "-", r["family"], r["system"], r["q"], r["makespan_ms"], r["source"]))
