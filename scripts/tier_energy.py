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


# Tags whose flow log is not a tier_logs run. EP=128 has no NVSwitch-style tier
# byte pass and needs none: the flow set is topology-independent (the EP 16/32/64
# logs from the glass, NVL-64 and HGX-8 runs are the same multiset) and this flow
# log is the EP=128 Arctic workload's, from the glass port-map run.
FLOWLOG = {
    "tier_ep128": os.path.join(os.path.dirname(DC), "fl_logs", "fl_ep128_arc.flowlog"),
}


def flowlog_path(tag):
    return FLOWLOG.get(tag, os.path.join(DC, tag + ".flowlog"))


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
    with open(flowlog_path(tag)) as fh:
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
    for tag, ep, nodes, makespan_ms, ms_note, sysname in rows:
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
            paper_ref="power", system=sysname, ep=ep, nodes=nodes, panels=panels,
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
                  "collapsed to a midpoint; static term is laser+tuning only"
                  + (" | " + ms_note if ms_note else ""))))
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
    main([("tier_ep16", 16, 128, 87.613, "", "glassfb"),
          ("tier_ep32", 32, 256, 77.918, "", "glassfb"),
          ("tier_ep64", 64, 512, 43.088, "", "glassfb"),
          # 200G/lane at EP=16 and EP=32, on the design point's own maps and hop
          # logs for the same reason as EP=64: the cabling is unchanged and
          # 1.15 pJ/bit is dynamic, so bytes x hops and therefore link J cannot
          # move. Only the static integral shortens.
          ("tier_ep16", 16, 128, 87.700,
           "200G/lane quoted rung q=533, 2x BDP, 0 timeouts; bytes and hops are the "
           "design point's; STATIC LASER+TUNE NOT RE-BUDGETED for 200G/lane",
           "glassfb_800"),
          ("tier_ep32", 32, 256, 75.253,
           "200G/lane quoted rung q=2133, 4x BDP, 0 timeouts; bytes and hops are the "
           "design point's; STATIC LASER+TUNE NOT RE-BUDGETED for 200G/lane",
           "glassfb_800"),
          # 200G/lane, EP=64. The SAME tier_ep64 hop log and the SAME flow log:
          # g64b800 runs ep64_gt.txt, the design point's cabling, so bytes x hops
          # are identical and the link term cannot move -- 1.15 pJ/bit is dynamic,
          # and the same bits over the same hops cost the same joules however fast
          # the link carries them. Only the static term moves, because it is a
          # power integrated over a shorter iteration.
          ("tier_ep64", 64, 512, 39.879,
           "200G/lane (GLASS_PORT_BW=800) quoted rung q=8533, 32x BDP, 0 timeouts; "
           "bytes and hops are the design point's (same ep64_gt.txt cabling and the "
           "same flow log) so link J is unchanged by construction and only the "
           "static term moves; STATIC LASER+TUNE NOT RE-BUDGETED -- 5.3 W/panel was "
           "costed for 100G/lane and is likely low for the higher-rate lanes",
           "glassfb_800"),
          # EP=128. The bytes are final; the makespan is not.
          #
          # Bytes x hops here come from a hop log the topology emitted WITHOUT
          # simulating traffic: scripts/hopdump_validate.sh builds the same
          # GlassFBTopology the runner builds (glassfb_hopdump) and asks it for the
          # same routes, so the classification is still the topology's own, from the
          # same adjacent_link predicate. It is validated red-then-green against the
          # real runs' hop logs at EP 16, 32 and 64: every shared pair's hop triple
          # agrees and all nine tier byte totals match exactly, while removing the
          # port map makes 172 triples disagree. 4.8 s at EP=128 against the hours a
          # traffic run would take, and zero flows unmatched by the hop log.
          #
          # Cabling is ep128_gt.txt, the map the g128 rungs run on -- NOT the
          # ep128_12_1_1.txt the flow log was captured under. That is the point of
          # the topology-independence check: the flow set is the workload's, the hop
          # counts are this cabling's.
          #
          # The makespan is the best HOLLOW rung, q=1066: glass EP=128 has no
          # timeout-free rung yet (four of six in, 601806 / 394052 / 238854 RTO at
          # q=533/1066/2133 and 6883 at q=17067) and may never get one. Only the
          # static term depends on it; link J is final either way.
          ("tier_ep128", 128, 1024, 266.337,
           "EP=128 hop log from glassfb_hopdump (topology's own classification, no "
           "traffic run; validated byte-for-byte against the EP 16/32/64 run hop logs "
           "by scripts/hopdump_validate.sh) on cabling ep128_gt.txt; flow set from "
           "fl_ep128_arc.flowlog, topology-independent; MAKESPAN IS PROVISIONAL -- "
           "the best hollow rung (q=4267, 107670 timeouts), not a quoted row, because "
           "this walk has no timeout-free rung; link J does not depend on it, static "
           "J does", "glassfb")])
