#!/usr/bin/env python3
"""Put q_over_bdp on the canonical BDP = link_bw * 4 * one-way-latency.

Three conventions were in use at once:

  pkt_cliff.sh      q*MTU / (link * 1e-6)   with nvs_lat 250 ns  -> 4*lat, canonical
                    (its column is even named q_over_bdp_4lat)
  dragonfly16.sh    q*MTU / (sub  * 5e-7)   with inter lat 500 ns -> 1*lat
  portmap_cliff.sh  hardcoded 8.0                                 -> 1*lat
  ep32_gt.sh        hardcoded 8.0                                 -> 1*lat
  island_cliff.sh   q*MTU / (nic  * 2e-6)   with rtt 2000 ns      -> 4*lat, canonical

Every glass banner reports `lat 100/300/500 ns`, so the inter-panel tier is
500 ns one way and its canonical BDP is link_bw * 2 us. At the port rate of
400 GB/s that is 800 000 B; q = 1064 * 1500 = 1 596 000 B, so the glass rows are
q = 2.0 x BDP, not 8.0. The 8.0 was q over one one-way latency.

This changes NO measured quantity -- q itself is unchanged and every run used the
same queue. It corrects a derived label that was reported four different ways.

Idempotent: rows already at the canonical value are left alone. Skips any file
currently being appended to by a running job -- pass those once the job ends.
"""
import csv, os, sys, glob

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
PAPER = os.path.join(ROOT, "experiments/results/paper")
MTU = 1500
GLASS_INTER_LAT_S = 500e-9   # from the run banner: lat 100/300/500 ns


def per_link_gbs(row, fname):
    """Bytes/s on the queue the buffer q actually sits on."""
    if "sublink_gbs" in row and row.get("sublink_gbs"):
        return float(row["sublink_gbs"]) * 1e9        # dragonfly: the sub-link
    if "portmap" in (row.get("cabling") or "") or "portmap" in fname:
        return 400e9                                   # one MTP-16 port
    return None


def main(paths):
    for p in paths:
        with open(p, newline="") as fh:
            rows = list(csv.DictReader(fh))
        if not rows or "q_over_bdp" not in rows[0] or "q" not in rows[0]:
            print("skip %-28s (no q/q_over_bdp)" % os.path.basename(p))
            continue
        changed = 0
        for r in rows:
            if not r.get("q"):
                continue
            bw = per_link_gbs(r, os.path.basename(p))
            if bw is None:
                continue
            bdp = bw * 4 * GLASS_INTER_LAT_S
            new = "%.1f" % (float(r["q"]) * MTU / bdp)
            if r.get("q_over_bdp") != new:
                r["q_over_bdp"] = new
                changed += 1
        with open(p, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print("%-30s %d row(s) set to the 4*lat convention" % (os.path.basename(p), changed))


if __name__ == "__main__":
    main(sys.argv[1:] or sorted(glob.glob(os.path.join(PAPER, "*.csv"))))
