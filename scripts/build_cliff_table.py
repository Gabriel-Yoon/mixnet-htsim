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
import csv, glob, os

PAPER = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/paper"
OUT = os.path.join(PAPER, "cliff_all.csv")

FIELDS = ["paper_ref", "family", "system", "model_name", "topk", "ep", "mb", "nodes",
          "q", "q_over_bdp", "rto_min_us", "mtu", "makespan_ms", "rtos",
          "quotable", "quotable_why", "fct_logdir", "source", "note"]

# files that carry cliff-figure rows, and how to name the system when absent
SOURCES = {
    "cliff.csv": None,
    "cliff_pkt.csv": None,
    "cliff_pkt_ep128.csv": None,
    "cliff_ep32_gt.csv": "glassfb",
    "cliff_ep32_gt_ksweep.csv": "glassfb",
    "cliff_ep64_gt.csv": "glassfb",
    "cliff_portmap.csv": "glassfb",
    "mb_sweep.csv": None,
    "pkt_vanishing_timeout.csv": None,
    "qplateau_ep32.csv": "glassfb",
    "qfine_ep32.csv": "glassfb",
}


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


out = []
for name, default_system in SOURCES.items():
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
                "model_name": pick(r, "model_name", "model"),
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
                "quotable": pick(r, "quotable"),
                "quotable_why": pick(r, "quotable_why"),
                "fct_logdir": pick(r, "fct_logdir"),
                "source": name,
                "note": pick(r, "note"),
            })

def _n(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


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
