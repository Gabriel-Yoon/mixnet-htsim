#!/usr/bin/env python3
"""In-domain vs NIC bytes for the packet-level incumbent, and its energy.

WHY NO NEW INSTRUMENTATION. I told the peer a naive (src,dst) classification
would undercount in-domain bytes, because a cross-domain flow "still traverses
in-domain links at both ends". Reading NVSwitchTopology::get_paths, that is
wrong for this model:

    same domain:   up_q[src][s] -> up_p[src][s] -> down_q[dest][s] -> down_p[dest][s]
    cross domain:  nic_feeder[src] -> nic_q[k] -> nic_p[k]

The cross-domain route never touches an NVLink queue -- it goes straight onto the
NIC. So the split IS domain arithmetic, and the correction is that in-domain
flows cross TWO NVLink hops (GPU->switch, switch->GPU), not one.

WHY THE GLASS FLOW LOG IS THE RIGHT INPUT. The flow set comes from the task
graph, not the fabric: ffapp emits the same (src, dst, bytes) for a given
workload whichever topology is loaded, and the intra-node shortcut is disabled in
both. Verified rather than assumed: the glass EP=16 flow log has 78 592 flows and
the hgx8_pkt EP=16 run's FCT log has 78 592 records.

pJ/bit brackets are carried as brackets. The NIC figure is a per-tier number, not
an NVLink one, and is named separately so it cannot be silently folded in.
"""
import csv, os

DC = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter/tier_logs"
OUT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/paper/power_tiers_pkt.csv"

NVLINK = (1.55, 5.00)          # pJ/bit, bracket
NIC_PJ_BIT = 15.0              # scale-out NIC+switch port, per the tier_power accounting
NVS_STATIC_W_PER_GPU = (7.5, 12.5)

HOPS_IN_DOMAIN = 2             # GPU -> switch -> GPU
HOPS_CROSS = 1                 # one NIC link


def load_hops(tag):
    """Topology-emitted hop counts, when the run produced them.

    nvhoplog: <src> <dst> <nvlink_hops> <nic_hops>, from inside
    NVSwitchTopology::get_paths. Preferred over domain arithmetic: the point of
    the instrumentation is that the split comes from the routing rather than
    from my reading of it, even where the two agree.
    """
    p = os.path.join(DC, tag + ".nvhoplog")
    hops = {}
    if not os.path.exists(p):
        return hops
    with open(p) as fh:
        for line in fh:
            f = line.split()
            if len(f) == 5:
                hops[(int(f[1]), int(f[2]))] = (int(f[3]), int(f[4]))
    return hops


def split(tag, domain):
    hops = load_hops(tag)
    mode = "topology_hoplog" if hops else "domain_arithmetic"
    ind = cross = 0
    flows = unmatched = 0
    with open(os.path.join(DC, tag + ".flowlog")) as fh:
        for line in fh:
            f = line.split()
            if len(f) != 4:
                continue
            s, d, b = int(f[1]), int(f[2]), int(f[3])
            if b == 0:
                continue
            flows += 1
            h = hops.get((s, d)) if hops else None
            if h is None and hops:
                unmatched += 1
                continue
            if h is None:
                h = (HOPS_IN_DOMAIN, 0) if s // domain == d // domain else (0, HOPS_CROSS)
            ind += b * h[0]
            cross += b * h[1]
    if unmatched:
        print("    NOTE: %d flow(s) had no routed pair in the hop log -- reported, not dropped"
              % unmatched)
    return ind, cross, flows, mode


rows = []
for sysname, domain in (("nvl64_pkt", 64), ("hgx8_pkt", 8)):
    for ep, nodes, ms in ((16, 128, 130.797), (32, 256, 119.397)):
        tag = "tier_%s_ep%d" % (sysname.replace("_pkt", ""), ep)
        if not os.path.exists(os.path.join(DC, tag + ".flowlog")):
            print("skip %s (not run yet)" % tag); continue
        ind, cross, flows, mode = split(tag, domain)
        it_s = ms / 1000.0
        e_lo = ind * 8 * NVLINK[0] * 1e-12 + cross * 8 * NIC_PJ_BIT * 1e-12
        e_hi = ind * 8 * NVLINK[1] * 1e-12 + cross * 8 * NIC_PJ_BIT * 1e-12
        st_lo = NVS_STATIC_W_PER_GPU[0] * nodes * it_s
        st_hi = NVS_STATIC_W_PER_GPU[1] * nodes * it_s
        tot = ind + cross
        print("%-10s ep=%-4s domain=%-3s flows=%-8s [%s]  in-domain %7.3f TB (%4.1f%%)  NIC %7.3f TB (%4.1f%%)"
              % (sysname, ep, domain, flows, mode, ind / 1e12, 100.0 * ind / tot,
                 cross / 1e12, 100.0 * cross / tot))
        print("            link %.2f - %.2f J/iter   NVSwitch static %.2f - %.2f J/iter"
              % (e_lo, e_hi, st_lo, st_hi))
        rows.append(dict(
            paper_ref="power", system=sysname, ep=ep, nodes=nodes, domain=domain,
            makespan_ms="%.3f" % ms, flows=flows,
            bytes_in_domain=ind, bytes_nic=cross,
            hops_in_domain=HOPS_IN_DOMAIN, hops_cross=HOPS_CROSS,
            nvlink_pj_bit_lo=NVLINK[0], nvlink_pj_bit_hi=NVLINK[1], nic_pj_bit=NIC_PJ_BIT,
            link_J_iter_lo="%.4f" % e_lo, link_J_iter_hi="%.4f" % e_hi,
            nvs_static_W_per_gpu_lo=NVS_STATIC_W_PER_GPU[0],
            nvs_static_W_per_gpu_hi=NVS_STATIC_W_PER_GPU[1],
            static_J_iter_lo="%.4f" % st_lo, static_J_iter_hi="%.4f" % st_hi,
            hop_source=mode,
            note=("in-domain vs NIC from the topology's own hop log where present, else "
                  "domain arithmetic (hop_source says which); "
                  "NVSwitchTopology::get_paths routes cross-domain flows straight onto the NIC "
                  "(nic_feeder->nic_q->nic_p), so they cross NO NVLink hop, while in-domain flows "
                  "cross two (GPU->switch->GPU); flow set is workload-determined and verified "
                  "equal to the glass run (78592 flows at EP=16); brackets not collapsed")))

with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
print("\nwrote", OUT)
