import csv, glob, os, re
ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
RE_Q = re.compile(r"NVSwitch queue:\s*(\d+)\s*pkt\s*\(([0-9.]+)x BDP")
banner = {}
for lg in glob.glob(os.path.join(ROOT, "src/clos/datacenter/pktcliff_logs", "*.log")):
    with open(lg, errors="replace") as fh:
        for line in fh:
            m = RE_Q.search(line)
            if m:
                banner[int(m.group(1))] = m.group(2); break
p = os.path.join(ROOT, "experiments/results/paper/cliff_pkt.csv")
rows = list(csv.DictReader(open(p, newline="")))
n = 0
for r in rows:
    q = int(float(r["q_nvs"])); b = banner.get(q * 1436 // 1500)
    if b and r.get("q_over_bdp_4lat") != b:
        print("  q_nvs=%s  %s -> %s (banner)" % (q, r["q_over_bdp_4lat"], b))
        r["q_over_bdp_4lat"] = b; n += 1
if rows:
    w = csv.DictWriter(open(p, "w", newline=""), fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
print("cliff_pkt.csv: %d row(s) set from the banner" % n)
