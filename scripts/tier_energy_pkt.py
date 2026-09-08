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
import csv, os, glob, re

DC = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter/tier_logs"
OUT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/paper/power_tiers_pkt.csv"

NVLINK = (1.55, 5.00)          # pJ/bit, bracket
# Scale-out NIC + switch port. 16.0, the LOW end of the 16-20 pJ/bit scale-out
# class in docs/interconnect_parameters.md (HotI'25 Tab. I, total incl.
# retimers) -- the same range scripts/tier_power.py (PJ_SCALEOUT) and
# scripts/whole_power2.py (PJ_NIC) already use. It was 15.0, attributed to
# "the tier_power accounting", which carries no such value; 15.0 was below
# every documented figure and had no source. The low end is also the
# conservative end: this is charged to the INCUMBENT's cross-domain bytes,
# so a larger number would flatter us.
NIC_PJ_BIT = 16.0
NVS_STATIC_W_PER_GPU = (7.5, 12.5)

HOPS_IN_DOMAIN = 2             # GPU -> switch -> GPU
HOPS_CROSS = 1                 # one NIC link


# Tags whose byte pass is not a tier_logs run. EP=128's flow log is the glass
# port-map run's: no NVSwitch byte pass at EP=128 was ever submitted, and none is
# needed, because the flow set is topology-independent (verified at EP 16/32/64 --
# the three fabrics' logs are the same multiset) and the split is domain
# arithmetic (verified equal to the topology hop log at all six pairs that have
# one). Named here so the row's input is readable in the code rather than hidden
# behind a symlink.
FLOWLOG = {
    "tier_nvl64_ep128": os.path.join(
        os.path.dirname(DC), "fl_logs", "fl_ep128_arc.flowlog"),
    # The same file: the flow set is the workload's, not the fabric's, and only
    # `domain` (8 vs 64) differs between these two rows.
    "tier_hgx8_ep128": os.path.join(
        os.path.dirname(DC), "fl_logs", "fl_ep128_arc.flowlog"),
}


def flowlog_path(tag):
    return FLOWLOG.get(tag, os.path.join(DC, tag + ".flowlog"))


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
    with open(flowlog_path(tag)) as fh:
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


RE_QBANNER = re.compile(r"NVSwitch queue:\s*(\d+)\s*pkt")


def banner_q(tag):
    """The queue the RUN reported, in payload-equivalent packets, or None.

    The runner passes -nvs_q in full-MTU packets and the topology prints the
    payload-equivalent count, so the two differ by a constant ~0.956 (1436/1500):
    544 -> 520, 1224 -> 1171. They name the same buffer. Reading it back is what
    makes the requested value in RUNS checkable rather than remembered -- if a
    row ever claims a buffer the run did not use, the ratio moves and the
    mismatch is printed beside the row.
    """
    for name in sorted(glob.glob(os.path.join(DC, tag + "_*.log")), reverse=True) + \
                [os.path.join(DC, tag + ".log")]:
        try:
            with open(name, errors="replace") as fh:
                for line in fh:
                    m = RE_QBANNER.search(line)
                    if m:
                        return int(m.group(1))
        except OSError:
            continue
    return None


rows = []
# ep -> (nodes, makespan_ms, q the BYTE PASS ran at, q the MAKESPAN was measured at),
# PER SYSTEM. Both differ between the two: the tier runs pass -nvs_q 544 for NVL-64 and
# 1224 for HGX-8, and each system's makespan is its own.
#
# Until this was keyed per system, both systems took NVL-64's makespan, so HGX-8's static
# energy was computed from 130.797/119.397 ms instead of its own 145.497/164.522 -- 11%
# low at EP=16 and 38% low at EP=32, on the term that dominates its budget, in the
# direction that flatters the incumbent. The banner cross-check below is what surfaced it:
# it reported HGX-8 running at 1171 pkt where the table claimed 544.
#
# q_bytes and q_makespan also differ from each other for NVL-64 at EP=32: the tier runs
# predate the vanishing-timeout walk and used 544, while the quoted makespan comes from
# 1088. Bytes do not depend on the buffer and the makespan enters only the static-energy
# time integral, but the row says so rather than leaving it to be reconstructed.
RUNS = {
    # nvl64_pkt (pinned) is UNCHANGED: L=50 gives exactly 20 ps/byte under both the
    # old integer arithmetic and the new exact one.
    "nvl64_pkt": ((16, 128, 130.797,  544,  544),
                  (32, 256, 119.397,  544, 1088),
                  (64, 512,  82.502, 2176, 2176),
                  # EP=128, quoted at q=2176. The makespan comes from a pre-fix
                  # binary and does not need re-measuring: nvl64_pkt's links are
                  # L=50, which is exactly 20 ps/byte under the old integer
                  # arithmetic and the new exact one. Batch 4 re-runs this cell on
                  # a drop-reporting build; if it does not reproduce 247.218, this
                  # row is wrong and the re-run will say so.
                  (128, 1024, 247.218, None, 2176)),
    # The striping control (S=1, L=900) is the other end of the bracket. Bytes and
    # hops are IDENTICAL to the pinned rows -- the same transfers over the same
    # two-hop paths -- so link energy is unchanged and only the static term moves,
    # because static is a power integrated over the iteration and the striped
    # iteration is shorter. Quoting the incumbent here is quoting it at its best
    # case on both axes at once: faster AND therefore less static energy.
    # q is the buffer the BYTE PASS ran at and q_makespan the buffer the MAKESPAN
    # was measured at; for these they are necessarily different, because the byte
    # pass is the pinned one and the makespan is the striped quoted row.
    # POST-FIX striped makespans; the byte pass is still the pinned one, since S
    # changes how a GPU's bandwidth is divided and not which links a packet crosses.
    "nvl64_pkt_s1": ((16, 128, 89.430,  544, 2400),
                     (32, 256, 69.989,  544, 4800),
                     (64, 512, 29.904, 2176, 9600),
                     # EP=128: first timeout-free rung of the six-rung walk,
                     # q=9600, zero timeouts and zero drops.
                     (128, 1024, 240.730, None, 9600)),
    # hgx8_pkt is UNCHANGED post-fix: it is bounded by the NIC tier at 100 GB/s,
    # a rate that divided 1000 exactly, so the +11% on its NVLink tier never
    # reached the makespan. Verified, not assumed: the post-fix walk returned
    # 145.497 / 164.522 / 144.519, identical to these.
    "hgx8_pkt":  ((16, 128, 145.497, 1224, 1224),
                  (32, 256, 164.522, 1224, 1224),
                  (64, 512, 144.519, 1224, 1224),
                  # EP=128, measured post-fix by batch 4 and quoted at its first
                  # rung by the drop-aware branch: 139 653 timeouts and ZERO
                  # measured drops, identical at q=1224, 2448 and 4896 -- the same
                  # buffer-invariant spurious-timeout signature as at EP<=64, so it
                  # is not recovering loss and the rule admits it. The pre-fix row
                  # this replaces was 365.733, 0.4% away; unlike nvl64_pkt its
                  # NVLink tier ran at 112.5 GB/s and did truncate, so it needed
                  # re-measuring rather than an argument.
                  (128, 1024, 364.295, None, 1224)),
}

# Which tier byte pass a system's rows are measured from. nvl64_pkt_s1 has no byte
# pass of its own and needs none: S changes how a GPU's bandwidth is divided, not
# which links a packet crosses, so its per-tier byte counts are the pinned ones.
BYTES_FROM = {"nvl64_pkt_s1": "nvl64"}

for sysname, domain in (("nvl64_pkt", 64), ("nvl64_pkt_s1", 64), ("hgx8_pkt", 8)):
    for ep, nodes, ms, q_bytes, q_ms in RUNS[sysname]:
        tag = "tier_%s_ep%d" % (BYTES_FROM.get(sysname, sysname.replace("_pkt", "")), ep)
        if not os.path.exists(flowlog_path(tag)):
            print("skip %s (not run yet)" % tag); continue
        ind, cross, flows, mode = split(tag, domain)
        bq = banner_q(tag)
        if q_bytes is None:
            # The EP=128 byte pass is a glass run and prints no NVSwitch queue
            # banner, so there is no buffer to record or check. Bytes do not
            # depend on the buffer; the column is left empty rather than filled
            # with a number this run never used.
            bq = None
        if bq is None:
            print("    NOTE: %s has no queue banner -- q recorded from the run table,"
                  " unverified" % tag)
        elif not (0.94 <= bq / float(q_bytes) <= 0.97):
            print("    MISMATCH: %s ran at %d pkt (banner) but the table says %d --"
                  " ratio %.4f is outside the 1436/1500 conversion" % (tag, bq, q_bytes,
                                                                      bq / float(q_bytes)))
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
            makespan_ms="%.3f" % ms, q=("" if q_bytes is None else q_bytes),
            q_makespan=q_ms,
            q_banner_pkt=(bq if bq is not None else ""),
            q_banner_ratio=("%.4f" % (bq / float(q_bytes)) if bq else ""),
            flows=flows,
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
                  "equal to the glass run (78592 flows at EP=16); NIC 16.0 pJ/bit is the LOW "
                  "(conservative) end of the 16-20 pJ/bit scale-out class, HotI'25 "
                  "Tab. I, total incl. retimers -- it was an unsourced 15.0, below "
                  "every documented figure, until this re-emission; "
                  "brackets not collapsed"
                  + (" | EP=128 bytes from the glass port-map byte pass "
                     "fl_logs/fl_ep128_arc.flowlog: the flow set is topology-independent "
                     "(EP 16/32/64 logs from glass, NVL-64 and HGX-8 are the same multiset) "
                     "and the split is domain arithmetic, which equals the topology hop log "
                     "exactly at all six pairs that have one; flowlog line count 4757504 "
                     "matches flows_total in the EP=128 rung rows"
                     if ep == 128 else ""))))

with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
print("\nwrote", OUT)
