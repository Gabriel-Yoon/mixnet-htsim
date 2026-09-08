#!/usr/bin/env python3
"""The copper arm's long-link energy, available BEFORE its runs finish.

WHY NO NEW HOP LOG IS NEEDED, verified rather than argued. Hop CLASSIFICATION is a
property of the topology's geometry and cabling, not of link rate or latency:
glassfb_hopdump run with the copper knobs (GLASS_OPT_BW=100, GLASS_OPT_LAT=400)
produces, at EP 16/32/64, hop triples that differ from the committed glass hop log
on ZERO of 2152 / 8392 / 33160 common pairs. hopdump_validate.sh had already shown
the same invariance to GLASS_DIM_A2A and GLASS_EP_PLACE.

So the copper arm moves exactly the same bytes over exactly the same hops as
glassfb_800. Only the pJ/bit of the distance->=2 tier changes. The MAKESPAN will
differ -- that is what the 18 jobs are measuring -- but the energy on that tier is
determined already.

WHAT IS AND IS NOT CLAIMED. This is the long-link tier ONLY. The electrical and
inter-panel tiers are untouched by the ablation and are not re-costed here. The
copper figure is the scale-out class from docs/interconnect_parameters.md, 16-20
pJ/bit total including retimers (HotI'25 Tab. I; SLDF), carried as a BRACKET
because that is what the document records. The glass figure is the paper's own
blended 1.15 pJ/bit, whose credibility caveat is recorded in that same document
and is not restated or resolved here.
"""
import csv, os

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
SRC = os.path.join(ROOT, "experiments/results/paper/power_tiers.csv")
OUT = os.path.join(ROOT, "experiments/results/paper/copper_energy.csv")

GLASS_PJ = 1.15
COPPER_PJ = (16.0, 20.0)

rows = [r for r in csv.DictReader(open(SRC))
        if r.get("system") == "glassfb_800" and r.get("ep") in ("16", "32", "64")]
assert rows, "no glassfb_800 rows at EP 16/32/64"

out = []
print("%-5s %-16s %-12s %-12s %-12s %s"
      % ("EP", "opt bytes-hops", "glass J", "copper16 J", "copper20 J", "copper/glass"))
for r in sorted(rows, key=lambda r: int(r["ep"])):
    b = float(r["bytes_opt"])
    bits = b * 8.0
    g = bits * GLASS_PJ * 1e-12
    c_lo = bits * COPPER_PJ[0] * 1e-12
    c_hi = bits * COPPER_PJ[1] * 1e-12
    print("%-5s %-16.3f %-12.3f %-12.3f %-12.3f %.1f-%.1fx"
          % (r["ep"], b / 1e12, g, c_lo, c_hi, c_lo / g, c_hi / g))
    out.append(dict(
        paper_ref="copper_energy", tier="intra_panel_distance_ge2", ep=r["ep"],
        nodes=r["nodes"], bytes_x_hops=int(b),
        glass_pj_bit=GLASS_PJ, copper_pj_bit_lo=COPPER_PJ[0], copper_pj_bit_hi=COPPER_PJ[1],
        glass_J_iter="%.4f" % g, copper_J_iter_lo="%.4f" % c_lo, copper_J_iter_hi="%.4f" % c_hi,
        ratio_lo="%.2f" % (c_lo / g), ratio_hi="%.2f" % (c_hi / g),
        source="power_tiers.csv bytes_opt; hop classification verified unchanged under the copper knobs",
        note=("LONG-LINK TIER ONLY -- the electrical and inter-panel tiers are untouched by "
              "the ablation and are not re-costed. Hop classification is a property of "
              "geometry and cabling, not link rate: glassfb_hopdump under GLASS_OPT_BW=100 "
              "GLASS_OPT_LAT=400 differs from the committed glass hop log on 0 of "
              "2152/8392/33160 common pairs at EP 16/32/64, so the copper arm moves the same "
              "bytes over the same hops and only the pJ/bit changes. Copper 16-20 pJ/bit is "
              "the scale-out class, total incl. retimers (HotI'25 Tab. I; SLDF), kept as a "
              "bracket. Glass 1.15 pJ/bit is the paper's own blended figure; its credibility "
              "caveat is in docs/interconnect_parameters.md and is not resolved here. "
              "MAKESPAN is NOT determined by this -- batch 12 is measuring it.")))

with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
    w.writeheader(); w.writerows(out)
print("\nwrote %s: %d row(s)" % (OUT, len(out)))
