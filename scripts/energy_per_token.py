#!/usr/bin/env python3
"""Energy-per-token model for Glass-FB vs fat-tree on the serving workloads.

Fills the axis the paper currently has no number for. The simulator reports
makespan only; the pJ/bit advantage that motivates the whole design never shows
up in a latency number, so it needs to be computed separately from the traffic
volumes the workload exports already carry.

Every accounting choice that could be argued either way is an explicit named
constant or CLI flag below, because several of them materially change the answer
and the paper currently leaves them implicit (see docs/energy_model.md):

  --charge {nic,hop}     per-NIC (what main.tex tab:power does today) vs
                         per-hop (what dragonfly/arXiv:2407.10290 does)
  --glass-pj             1.15 (headline) .. 2.62 (paper's own conservative end)
  --budget {used,provisioned}
                         charge the ~19 waveguides the design actually lights,
                         or all 60 that the 7.66 TB/s / ~70 W figure assumes

Usage:
    python3 scripts/energy_per_token.py \
        --workload-dir experiments/pb_workloads/json \
        --out experiments/results/energy_per_token.csv
"""
import argparse
import csv
import glob
import json
import os

# ---------------------------------------------------------------- link energy
# pJ/bit by link class. Sources in docs/interconnect_parameters.md.
PJ_RDL = 0.5      # in-package electrical RDL, distance-1 neighbours (short-reach
                  # XSR SerDes class: 1 pJ/bit measured at 112G PAM-4 over <100um;
                  # halved here as the RDL run is shorter still. Conservative
                  # alternative: use 1.0.
PJ_GLASS = 1.15   # passive glass waveguide, paper headline (range to 2.62)
PJ_FIBER = 1.15   # inter-panel fibre, same passive-link basis as intra-panel
PJ_COPPER = 20.0  # copper cable long-reach hop, dragonfly H_l
PJ_COPPER_SHORT = 2.0  # copper short-reach hop (intra-cabinet), dragonfly H_sr

# ------------------------------------------------------------------- topology
PANEL = 16        # GPUs per panel
PCOLS = PROWS = 4  # intra-panel grid

# Waveguides per GPU: the design lights ~19 of the 60 the package fields.
# main.tex derives ~70 W/GPU from all 60 (7.66 TB/s); the links the simulator
# actually models correspond to ~19.
WG_USED, WG_PROVISIONED = 19, 60
WG_BW_GBPS = 128.0  # one waveguide = 32 lambda x 32 Gb/s = 128 GB/s


def glassfb_hops(ep):
    """Average link traversals per alltoall byte, and the share on each link class.

    Intra-panel FB (4x4, degree 6 = 3 row + 3 col peers) has diameter 2: a peer
    sharing a row or column is 1 hop, anything else is 2. Distance-1 neighbours
    ride the RDL, everything else the glass waveguide. Inter-panel is XY
    dimension-order over the 4-edge mesh, each panel hop preceded/followed by an
    intra-panel leg to reach the gateway GPU.
    """
    panels = max(1, -(-ep // PANEL))
    peers = max(1, ep - 1)
    intra_peers = min(PANEL - 1, peers)
    inter_peers = peers - intra_peers

    # --- intra-panel: of the 15 other GPUs in a 4x4 panel, 6 share a row/col
    #     (1 hop) and 9 do not (2 hops via a relay).
    direct = min(6, intra_peers)
    relayed = max(0, intra_peers - direct)
    # of the 6 direct peers, 4 are grid-adjacent (RDL), 2 are far (waveguide)
    rdl_links = direct * (4.0 / 6.0)
    wg_links = direct * (2.0 / 6.0) + relayed * 2.0  # relay legs are waveguide

    # --- inter-panel: mean XY hop count over a panels-wide mesh grid
    if panels <= 1:
        mesh_hops = 0.0
    else:
        ppc = int(panels ** 0.5) or 1
        while ppc > 1 and panels % ppc:
            ppc -= 1
        ppr = panels // ppc
        # mean |dx|+|dy| over an ppr x ppc grid, excluding self
        tot = n = 0
        for r1 in range(ppr):
            for c1 in range(ppc):
                for r2 in range(ppr):
                    for c2 in range(ppc):
                        if (r1, c1) != (r2, c2):
                            tot += abs(r1 - r2) + abs(c1 - c2)
                            n += 1
        mesh_hops = tot / n if n else 0.0

    # each inter-panel flow: 1 intra-panel leg to the gateway at each end
    # (waveguide) plus mesh_hops fibre hops
    inter_wg_links = inter_peers * 2.0
    inter_fiber_links = inter_peers * mesh_hops

    total_flows = peers
    return {
        "rdl": rdl_links / total_flows,
        "glass": (wg_links + inter_wg_links) / total_flows,
        "fiber": inter_fiber_links / total_flows,
        "panels": panels,
    }


def fattree_hops(ep):
    """Average link traversals per byte in a 3-tier fat-tree.

    server -> edge -> agg -> core -> agg -> edge -> server. Same-edge pairs
    traverse 2 links, same-pod 4, cross-pod 6. With k-ary-3 and ep endpoints the
    great majority of an alltoall's peers are cross-pod, so this is dominated by
    the 6-link case; the shares below are computed from the standard fat-tree
    fan-out rather than assumed.
    """
    k = 4
    while (k ** 3) // 4 < ep:
        k += 2
    per_edge = k // 2               # servers under one edge switch
    per_pod = (k // 2) ** 2         # servers in one pod
    peers = max(1, ep - 1)

    same_edge = min(per_edge - 1, peers)
    same_pod = min(max(0, per_pod - per_edge), peers - same_edge)
    cross_pod = max(0, peers - same_edge - same_pod)

    links = same_edge * 2 + same_pod * 4 + cross_pod * 6
    # intra-pod links are short-reach (in-cabinet), core links long-reach
    short = same_edge * 2 + same_pod * 4 + cross_pod * 4
    long = cross_pod * 2
    return {"short": short / peers, "long": long / peers, "k": k}


def energy_joules(bits, per_bit_pj):
    return bits * per_bit_pj * 1e-12


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workload-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--charge", choices=["nic", "hop"], default="hop")
    ap.add_argument("--glass-pj", type=float, default=PJ_GLASS)
    ap.add_argument("--copper-pj", type=float, default=PJ_COPPER)
    ap.add_argument("--budget", choices=["used", "provisioned"], default="used")
    args = ap.parse_args()

    rows = []
    for path in sorted(glob.glob(os.path.join(args.workload_dir, "*.json"))):
        d = json.load(open(path))
        ep = d["ep"]
        tokens = sum(d["local_tokens"])
        if not tokens:
            continue
        bits = (d["total_dispatch_bytes"] + d["total_combine_bytes"]) * 8

        g = glassfb_hops(ep)
        f = fattree_hops(ep)

        if args.charge == "hop":
            e_glass = (
                energy_joules(bits * g["rdl"], PJ_RDL)
                + energy_joules(bits * g["glass"], args.glass_pj)
                + energy_joules(bits * g["fiber"], args.glass_pj)
            )
            e_ft = (
                energy_joules(bits * f["short"], PJ_COPPER_SHORT)
                + energy_joules(bits * f["long"], args.copper_pj)
            )
            glass_hops = g["rdl"] + g["glass"] + g["fiber"]
            ft_hops = f["short"] + f["long"]
        else:
            # per-NIC: every byte charged once at each endpoint's link rate,
            # which is what main.tex tab:power does today.
            e_glass = energy_joules(bits, args.glass_pj)
            e_ft = energy_joules(bits, args.copper_pj)
            glass_hops = ft_hops = 1.0

        if args.budget == "provisioned":
            # charge the full 60-waveguide package budget rather than the lit
            # subset, matching how the ~70 W/GPU headline figure is derived
            e_glass *= WG_PROVISIONED / WG_USED

        rows.append({
            "workload": os.path.basename(path).replace(".json", ""),
            "ep": ep,
            "panels": g["panels"],
            "tokens": tokens,
            "bytes_total": bits // 8,
            "glassfb_hops_per_byte": round(glass_hops, 3),
            "fattree_hops_per_byte": round(ft_hops, 3),
            "glassfb_J_per_iter": round(e_glass, 6),
            "fattree_J_per_iter": round(e_ft, 6),
            "glassfb_uJ_per_token": round(e_glass / tokens * 1e6, 4),
            "fattree_uJ_per_token": round(e_ft / tokens * 1e6, 4),
            "energy_advantage_x": round(e_ft / e_glass, 2) if e_glass else "",
        })

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print(f"charge={args.charge} glass={args.glass_pj} copper={args.copper_pj} "
          f"budget={args.budget}")
    print(f"wrote {len(rows)} rows -> {args.out}")
    adv = [r["energy_advantage_x"] for r in rows if r["energy_advantage_x"] != ""]
    if adv:
        print(f"energy advantage (fat-tree J / Glass-FB J): "
              f"min {min(adv):.2f}x  max {max(adv):.2f}x  mean {sum(adv)/len(adv):.2f}x")


if __name__ == "__main__":
    main()
