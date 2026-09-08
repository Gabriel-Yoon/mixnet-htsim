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
differ -- that is what the 18 jobs of batch 12 are measuring -- but the energy on
that tier is determined already.

BOTH SIDES ARE BRACKETS, because that is how the paper quotes them. Glass is
1.15 (PanelScale blended) to 2.62 (components-based conservative); copper is the
16-20 pJ/bit scale-out class, total including retimers (HotI'25 Tab. I; SLDF),
from docs/interconnect_parameters.md. An earlier version of this file emitted the
glass low end alone and the manuscript had to re-derive the upper end by hand,
which is the re-derivation an artifact exists to prevent.

NO RATIO IS EMITTED, deliberately. The bytes and the hops are identical between
the two arms, so any ratio computed here is exactly the pJ/bit ratio -- 16/1.15
and so on -- and reporting it would be quoting an input back as though it were a
result. The absolute joules are the content, and the makespan is the measurement.

SCOPE: the distance->=2 intra-panel tier ONLY. The electrical and inter-panel
tiers are untouched by the ablation and are not re-costed here. The credibility
caveat attached to 1.15 pJ/bit stands unchanged in docs/interconnect_parameters.md
and is not resolved by this ablation.
"""
import csv, os

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
SRC = os.path.join(ROOT, "experiments/results/paper/power_tiers.csv")
OUT = os.path.join(ROOT, "experiments/results/paper/copper_energy.csv")

GLASS_PJ = (1.15, 2.62)
COPPER_PJ = (16.0, 20.0)

NOTE = ("distance->=2 intra-panel tier ONLY; the electrical and inter-panel tiers are "
        "untouched by the ablation and are not re-costed. Hop classification is a property "
        "of geometry and cabling, not link rate: glassfb_hopdump under GLASS_OPT_BW=100 "
        "GLASS_OPT_LAT=400 differs from the committed glass hop log on 0 of 2152/8392/33160 "
        "common pairs at EP 16/32/64, so the copper arm moves the same bytes over the same "
        "hops and only the pJ/bit changes. Both sides are brackets: glass 1.15-2.62 "
        "(PanelScale blended / components-based), copper 16-20 scale-out class total incl. "
        "retimers (HotI'25 Tab. I; SLDF). No ratio column: bytes and hops are identical "
        "between the arms so any ratio is exactly the pJ/bit ratio, an input quoted back. "
        "MAKESPAN is NOT determined by this -- batch 12 is measuring it. The credibility "
        "caveat on 1.15 pJ/bit stands in docs/interconnect_parameters.md.")

rows = [r for r in csv.DictReader(open(SRC))
        if r.get("system") == "glassfb_800" and r.get("ep") in ("16", "32", "64")]
assert rows, "no glassfb_800 rows at EP 16/32/64"

out = []
print("%-5s %-16s %-18s %-18s" % ("EP", "opt bytes-hops", "glass J 1.15-2.62", "copper J 16-20"))
for r in sorted(rows, key=lambda x: int(x["ep"])):
    b = float(r["bytes_opt"])
    bits = b * 8.0
    g_lo, g_hi = bits * GLASS_PJ[0] * 1e-12, bits * GLASS_PJ[1] * 1e-12
    c_lo, c_hi = bits * COPPER_PJ[0] * 1e-12, bits * COPPER_PJ[1] * 1e-12
    print("%-5s %-16.3f %-18s %-18s" % (r["ep"], b / 1e12,
                                        "%.3f-%.3f" % (g_lo, g_hi),
                                        "%.3f-%.3f" % (c_lo, c_hi)))
    out.append(dict(
        paper_ref="copper_energy", tier="intra_panel_distance_ge2", ep=r["ep"],
        nodes=r["nodes"], bytes_x_hops=int(b),
        glass_pj_bit_lo=GLASS_PJ[0], glass_pj_bit_hi=GLASS_PJ[1],
        copper_pj_bit_lo=COPPER_PJ[0], copper_pj_bit_hi=COPPER_PJ[1],
        glass_J_iter_lo="%.4f" % g_lo, glass_J_iter_hi="%.4f" % g_hi,
        copper_J_iter_lo="%.4f" % c_lo, copper_J_iter_hi="%.4f" % c_hi,
        source="power_tiers.csv bytes_opt; hop classification verified unchanged under the copper knobs",
        note=NOTE))

with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
    w.writeheader(); w.writerows(out)
print("\nwrote %s: %d row(s)" % (OUT, len(out)))
