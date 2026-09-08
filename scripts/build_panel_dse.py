#!/usr/bin/env python3
"""panel_dse.csv and load_panel.csv, DERIVED from cliff_postfix.csv.

Derived, not assembled. cliff_postfix.csv is what collect_rungs.py produces after
applying the declared ladder, the gap check and the double-write refusal, so it is
the single authority on which rung of a walk is quoted. This script adds the
geometry columns a reader of the DSE figure needs -- grid, topo, opt_bw, maxdist --
and changes nothing else. If a row is quotable here it is because collect_rungs
said so.

EVERY RUNG IS EMITTED, not only the quoted one. The finding in this arm is the
BUFFER AXIS: the mesh reaches a lower makespan than the butterfly only above its
threshold and collapses below it, while the butterfly is nearly flat from 2x BDP
up. A file containing only quoted rows cannot show that, and the quoted rows of
the two arms sit at different buffers, so a bar chart of them is not a controlled
comparison. `quotable` marks which row the vanishing-timeout rule selects.

THE 4x4 DESIGN POINT IS INCLUDED AS A REFERENCE ROW per EP, marked arm=4x4, so the
figure can draw its line without the plotting script having to know which walk
name means the design point.
"""
import csv, os, sys

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
SRC = os.path.join(ROOT, "experiments/results/paper/cliff_postfix.csv")
DSE = os.path.join(ROOT, "experiments/results/paper/panel_dse.csv")
LOAD = os.path.join(ROOT, "experiments/results/paper/load_panel.csv")

GEOM = {
    "glassfb_8x8":     dict(arm="fb",   grid="8x8", topo="flattened_butterfly", opt_bw="128", maxdist="0"),
    "glassfb_mesh8x8": dict(arm="mesh", grid="8x8", topo="mesh",                opt_bw="128", maxdist="1"),
    "glassfb_800":     dict(arm="4x4",  grid="4x4", topo="flattened_butterfly", opt_bw="384", maxdist="0"),
}
# The 4x4 walk names that ARE the design point, one per EP. The mb-variant walks
# (g16b800m4 and friends) are the load sweep, not the design point, and must not
# become a second reference line at EP=16.
DESIGN_WALK = {"g16b800", "g32b800", "g64b800", "g128b800"}

FIELDS = ["paper_ref", "arm", "grid", "topo", "opt_bw_GBps", "port_bw_GBps", "maxdist",
          "ep", "nodes", "mb", "cabling", "walk", "q", "q_over_bdp", "makespan_ms",
          "rtos", "drops", "quotable", "quotable_why", "quoted_by", "link_rate_fixed",
          "binary_sha", "source", "note"]

rows = list(csv.DictReader(open(SRC)))
out, seen_ep, dropped = [], set(), []
for r in rows:
    sysname = (r.get("system") or "").strip()
    g = GEOM.get(sysname)
    if not g:
        continue
    walk = (r.get("walk") or "").strip()
    if sysname == "glassfb_800" and walk not in DESIGN_WALK:
        continue                       # the mb sweep is not the design point
    if not (r.get("makespan_ms") or "").strip():
        continue
    # A BLOCKED row is not a slow row, it is a DIFFERENT FABRIC. status=blocked
    # with relayed_pairs>0 means a flow could not use a cabled inter-panel link
    # and was relayed instead, so the run did not measure the topology it names.
    # Every EP=128 rung of both arms is in this state -- p64_ep128.txt cables 28
    # panel pairs and the workload needs 36 -- and one of those rows reads
    # 19934.507 ms, which is exactly the kind of number that ends up on an axis
    # if the file merely omits to mention it is invalid. They are dropped here
    # and counted out loud.
    if (r.get("status") or "").strip() != "sweep" or (r.get("relayed_pairs") or "0").strip() not in ("", "0"):
        dropped.append((r.get("system", ""), r.get("ep", ""), r.get("q", ""),
                        (r.get("status") or "").strip(), (r.get("relayed_pairs") or "").strip()))
        continue
    out.append({
        "paper_ref": "panel_dse", "arm": g["arm"], "grid": g["grid"], "topo": g["topo"],
        "opt_bw_GBps": g["opt_bw"], "port_bw_GBps": "800", "maxdist": g["maxdist"],
        "ep": r.get("ep", ""), "nodes": r.get("nodes", ""), "mb": r.get("mb", ""),
        "cabling": r.get("cabling", ""), "walk": walk, "q": r.get("q", ""),
        "q_over_bdp": r.get("q_over_bdp", ""), "makespan_ms": r.get("makespan_ms", ""),
        "rtos": r.get("rtos", ""), "drops": r.get("drops", ""),
        "quotable": r.get("quotable", ""), "quotable_why": r.get("quotable_why", ""),
        "quoted_by": r.get("quoted_by", ""),
        "link_rate_fixed": r.get("link_rate_fixed", ""),
        "binary_sha": r.get("binary_sha", ""), "source": "cliff_postfix.csv",
        "note": ("derived from cliff_postfix.csv, which applies the declared ladder and "
                 "the gap check; every rung is present, quotable marks the one the "
                 "vanishing-timeout rule selects; arm=4x4 rows are the design-point "
                 "reference, not part of the 8x8 sweep"),
    })
    if g["arm"] != "4x4":
        seen_ep.add((g["arm"], r.get("ep", "")))

out.sort(key=lambda r: (int(r["ep"] or 0), r["arm"], float(r["q"] or 0)))
with open(DSE, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=FIELDS); w.writeheader(); w.writerows(out)

have = {e for a, e in seen_ep}
want = {"16", "32", "64", "128"}
missing = sorted(want - have, key=int)
print("wrote %s: %d row(s)" % (DSE, len(out)))
for ep in sorted(want, key=int):
    arms = [a for a, e in seen_ep if e == ep]
    q = [r for r in out if r["ep"] == ep and r["quotable"] == "yes" and r["arm"] != "4x4"]
    print("  EP=%-4s arms present: %-14s quoted: %s"
          % (ep, ",".join(sorted(arms)) or "none",
             ", ".join("%s %s ms @ %sx BDP" % (r["arm"], r["makespan_ms"], r["q_over_bdp"]) for r in q) or "none"))
if dropped:
    eps = sorted({d[1] for d in dropped}, key=int)
    print("  EXCLUDED %d row(s) with status!=sweep or relayed_pairs>0, at EP %s -- "
          "these did not measure the topology they name and are NOT plottable"
          % (len(dropped), ", ".join(eps)), file=sys.stderr)
if missing:
    print("  NOT IN THIS FILE: EP %s -- attempted and excluded, see the note column"
          % ", ".join(missing), file=sys.stderr)

# ---- the EP=16 load panel, three fabrics x four microbatches -------------------
LOAD_SYS = {"glassfb_800": "glass_200G", "nvl64_pkt_s1": "nvl64_striped", "hgx8_pkt": "hgx8"}
lrows = []
for r in rows:
    s = LOAD_SYS.get((r.get("system") or "").strip())
    if not s or (r.get("ep") or "") != "16":
        continue
    if (r.get("quotable") or "") != "yes":
        continue
    mb = (r.get("mb") or "").strip() or "8"
    lrows.append(dict(paper_ref="load_panel", system=s, ep="16", mb=mb,
                      walk=r.get("walk", ""), q=r.get("q", ""),
                      q_over_bdp=r.get("q_over_bdp", ""),
                      makespan_ms=r.get("makespan_ms", ""), rtos=r.get("rtos", ""),
                      drops=r.get("drops", ""), quotable_why=r.get("quotable_why", ""),
                      link_rate_fixed=r.get("link_rate_fixed", ""),
                      binary_sha=r.get("binary_sha", ""), source="cliff_postfix.csv"))
lrows.sort(key=lambda r: (r["system"], int(r["mb"])))
with open(LOAD, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(lrows[0].keys())); w.writeheader(); w.writerows(lrows)
print("\nwrote %s: %d quoted row(s)" % (LOAD, len(lrows)))
by = {}
for r in lrows:
    by.setdefault(r["system"], {})[r["mb"]] = r["makespan_ms"]
print("  %-16s %s" % ("system", "  ".join("mb=%-8s" % m for m in ("4", "8", "16", "32"))))
for s in sorted(by):
    print("  %-16s %s" % (s, "  ".join("%-11s" % by[s].get(m, "-") for m in ("4", "8", "16", "32"))))
