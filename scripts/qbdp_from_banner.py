#!/usr/bin/env python3
"""Take q_over_bdp for the NVLink sweep from the run banner, not from arithmetic.

I recomputed the multiple by hand as q*1500/BDP and got 2.04/4.08/8.16/16.32/
32.64. The simulator prints its own, computed from the MSS (1436 B) rather than
the 1500 B frame: 1.95/3.91/7.81/15.62/31.25. The banner is what the run used,
so the banner is the number.

Same rule as the status fields, applied to a quantity I derived myself: read it
off the run, do not reconstruct it.
"""
import csv, glob, os, re

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
DC = os.path.join(ROOT, "src/clos/datacenter")
RE_Q = re.compile(r"NVSwitch queue:\s*(\d+)\s*pkt\s*\(([0-9.]+)x BDP")

# q_pkts as the binary reports it -> multiple as the binary reports it
banner = {}
for lg in glob.glob(os.path.join(DC, "nvs_logs", "*.log")) + \
          glob.glob(os.path.join(DC, "nvsout_logs", "*.log")):
    try:
        with open(lg, errors="replace") as fh:
            for line in fh:
                m = RE_Q.search(line)
                if m:
                    banner[int(m.group(1))] = m.group(2)
                    break
    except OSError:
        pass

# the CSV records the q we PASSED (1500 B units); the banner reports the q the
# simulator built (MSS units). q_built = floor(q_passed * 1436/1500).
def built(q_passed):
    return int(q_passed * 1436 // 1500)

print("banner multiples found for built-q:", sorted(banner))

for name in ("nvl64_ksweep.csv", "nvl64_ksweep_hi.csv"):
    p = os.path.join(ROOT, "experiments/results/paper", name)
    with open(p, newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        continue
    n = 0
    for r in rows:
        qp = int(float(r["q_pkts"]))
        b = banner.get(built(qp)) or banner.get(built(qp) + 1) or banner.get(built(qp) - 1)
        if b and r.get("q_over_bdp") != b:
            r["q_over_bdp"] = b
            n += 1
        elif not b:
            r["q_over_bdp"] = ""      # rather than leave a hand-computed value
    with open(p, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("%-24s %d row(s) set from the banner" % (name, n))
