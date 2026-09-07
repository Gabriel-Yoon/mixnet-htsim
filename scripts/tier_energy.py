#!/usr/bin/env python3
"""Energy per iteration from measured bytes x measured hops, with brackets.

Inputs, both produced by the same run:
  <tag>.flowlog   "flowlog: src dst bytes"        every flow, from TcpSrc::set_flowsize
  <tag>.hoplog    "hoplog: src dst elec opt inter" the topology's own hop classification

Bytes on a tier = sum over flows of bytes x (hops of that tier on that flow's
route). A flow crossing two electrical hops is charged twice, because it moves
its bytes twice. Flows whose pair never appears in the hop log are reported
separately rather than dropped -- that would be a silent undercount, and an
undercount flatters us.

Energy brackets are carried through as brackets; no midpoint is invented.
  glass waveguide   1.15 - 2.62 pJ/bit   + 1 pJ/bit RDL for the electrical tier
  NVLink            1.55 - 5.00 pJ/bit
Static terms are per the agreed accounting and are NOT scaled by traffic:
  laser + thermal tuning   5.3 W per panel
  NVSwitch                12.5 / 7.5 W per GPU

Every number that is not measured here is named in the CSV note.
"""
import csv, os, sys, collections

DC = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter/tier_logs"
OUT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/paper/power_tiers.csv"

# pJ/bit brackets
GLASS_WG = (1.15, 2.62)
RDL_PJ = 1.0            # electrical RDL adder, per bit, on the electrical tier
NVLINK = (1.55, 5.00)

LASER_TUNE_W_PER_PANEL = 5.3


def load(tag):
    hops = {}
    with open(os.path.join(DC, tag + ".hoplog")) as fh:
        for line in fh:
            f = line.split()
            if len(f) == 6:
                hops[(int(f[1]), int(f[2]))] = (int(f[3]), int(f[4]), int(f[5]))
    tiers = collections.Counter()
    flows = unmatched = 0
    unmatched_bytes = 0
    with open(os.path.join(DC, tag + ".flowlog")) as fh:
        for line in fh:
            f = line.split()
            if len(f) != 4:
                continue
            s, d, b = int(f[1]), int(f[2]), int(f[3])
            flows += 1
            if b == 0:
                continue
            h = hops.get((s, d))
            if h is None:
                unmatched += 1
                unmatched_bytes += b
                continue
            tiers["elec"] += b * h[0]
            tiers["opt"] += b * h[1]
            tiers["inter"] += b * h[2]
    return tiers, flows, unmatched, unmatched_bytes


def main(rows):
    out = []
    for tag, ep, nodes, makespan_ms in rows:
        try:
            tiers, flows, unm, unm_b = load(tag)
        except OSError as e:
            print("skip %s: %s" % (tag, e)); continue
        panels = nodes // 16
        it_s = makespan_ms / 1000.0
        # inter-panel and optical intra-panel both ride waveguide; electrical adds RDL
        def energy(pj_wg):
            e_opt = (tiers["opt"] + tiers["inter"]) * 8 * pj_wg * 1e-12
            e_ele = tiers["elec"] * 8 * (pj_wg + RDL_PJ) * 1e-12
            return e_opt + e_ele
        e_lo, e_hi = energy(GLASS_WG[0]), energy(GLASS_WG[1])
        static_j = LASER_TUNE_W_PER_PANEL * panels * it_s
        tot_b = sum(tiers.values())
        print("%-12s ep=%-4s panels=%-3s flows=%-8s unmatched=%-6s (%.3f TB)" %
              (tag, ep, panels, flows, unm, unm_b / 1e12))
        for k in ("elec", "opt", "inter"):
            print("    %-6s %8.3f TB  (%5.1f%%)" %
                  (k, tiers[k] / 1e12, 100.0 * tiers[k] / tot_b if tot_b else 0))
        print("    link energy/iter  %.2f - %.2f J    static (laser+tune) %.2f J" %
              (e_lo, e_hi, static_j))
        out.append(dict(
            paper_ref="power", system="glassfb", ep=ep, nodes=nodes, panels=panels,
            makespan_ms="%.3f" % makespan_ms,
            bytes_elec=tiers["elec"], bytes_opt=tiers["opt"], bytes_inter=tiers["inter"],
            flows_total=flows, flows_unmatched=unm, bytes_unmatched=unm_b,
            glass_pj_bit_lo=GLASS_WG[0], glass_pj_bit_hi=GLASS_WG[1], rdl_pj_bit=RDL_PJ,
            nvlink_pj_bit_lo=NVLINK[0], nvlink_pj_bit_hi=NVLINK[1],
            link_J_iter_lo="%.4f" % e_lo, link_J_iter_hi="%.4f" % e_hi,
            static_laser_tune_W_per_panel=LASER_TUNE_W_PER_PANEL,
            static_J_iter="%.4f" % static_j,
            note=("bytes x hops from GLASS_LOG_FLOWS and the topology's own GLASS_LOG_HOPS "
                  "classification; electrical tier carries +1 pJ/bit RDL; brackets not "
                  "collapsed to a midpoint; static term is laser+tuning only")))
    if out:
        with open(OUT, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
            w.writeheader(); w.writerows(out)
        print("\nwrote", OUT)


if __name__ == "__main__":
    # tag, ep, nodes, makespan of the row these bytes belong to
    # makespan is the QUOTED row's for that EP -- its vanishing-timeout point.
    # EP=64 is 39.395 ms at q=17067 (64x BDP), zero timeouts and zero measured drops.
    # POST-FIX makespans (link-rate truncation fixed, 9ac4f76). Bytes x hops are
    # rate-independent, so only the static term moves.
    main([("tier_ep16", 16, 128, 87.613),
          ("tier_ep32", 32, 256, 77.918),
          ("tier_ep64", 64, 512, 43.088)])
