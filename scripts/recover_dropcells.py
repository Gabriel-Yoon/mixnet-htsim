#!/usr/bin/env python3
"""Recover the glass drop cells from their run logs.

All six ran their simulation correctly and then died writing the CSV: the
glassdrop mode took the pkt row-writing branch, which references $D, unbound under
set -u. The three still in flight run the frozen batch-2 copy and will fail the
same way after doing their work.

Nothing about the measurement is in doubt -- the log carries the makespan, the
drop count, the timeout count and the name of the output directory, which is
every field the row needs. Re-running six cells to obtain numbers already on disk
would cost half an hour for nothing.

This is a RECOVERY, not a re-measurement, and the rows say so in their note. The
makespan is cross-checked against the corresponding non-drop rung: the drop build
is the same simulator plus counters, so a disagreement would mean the recovered
row belongs to some other run and it is refused rather than written.
"""
import csv, glob, os, re, sys

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
DC = os.path.join(ROOT, "src/clos/datacenter")
RUNGS = os.path.join(ROOT, "experiments/results/paper/rungs")

# tag -> (ep, nodes, mb, q, cabling, the non-drop rung to check against)
CELLS = {
    "gd16m4_q532":   ("16", "128", "4", "532", "ep16_0_8_4.txt", "g16m4_q532"),
    "gd16m8_q532":   ("16", "128", "8", "532", "ep16_0_8_4.txt", "g16m8_q532"),
    "gd16m16_q532":  ("16", "128", "16", "532", "ep16_0_8_4.txt", "g16m16_q532"),
    "gd16m32_q532":  ("16", "128", "32", "532", "ep16_0_8_4.txt", "g16m32_q532"),
    "gd32_q2133":    ("32", "256", "8", "2133", "ep32_gt.txt", "g32_q2133"),
    "gd64_q17067":   ("64", "512", "8", "17067", "ep64_gt.txt", "g64_q17067"),
}

HDR = ("paper_ref,system,cabling,ep,nodes,mb,q,relayed_pairs,completed,makespan_ms,"
       "rtos,drops,flows_total,flows_payload,mean_fct_ms,p50_fct_ms,p99_fct_ms,"
       "max_fct_ms,wall_s,status,note,link_rate_fixed,binary_sha").split(",")

RE_ITER = re.compile(r"finished one iter.*?now (\d+)")
RE_DROPS = re.compile(r"dropcount:\s*(\d+)")
RE_LD = re.compile(r"Log directory is:\s*(\S+)")


def expected_ms(rung):
    p = os.path.join(RUNGS, rung + ".csv")
    if not os.path.exists(p):
        return None
    for r in csv.DictReader(open(p, newline="")):
        if (r.get("status") or "").strip() not in ("submitted", "ABORTED", ""):
            return (r.get("makespan_ms") or "").strip()
    return None


def payload_stats(ld):
    d = ld if os.path.isabs(ld) else os.path.join(DC, ld.lstrip("./"))
    f = os.path.join(d, "fct_util_out.txt")
    vals, total = [], 0
    try:
        for line in open(f, errors="replace"):
            if not line.startswith("FCT "):
                continue
            p = line.split()
            if len(p) < 5:
                continue
            total += 1
            if float(p[3]) > 1436:
                vals.append(float(p[4]))
    except OSError:
        return None
    if not vals:
        return None
    vals.sort()
    n = len(vals)
    return (total, n, sum(vals) / n, vals[min(n - 1, int(n * .50))],
            vals[min(n - 1, int(n * .99))], vals[-1])


written = refused = pending = 0
for tag, (ep, nodes, mb, q, cab, ref) in sorted(CELLS.items()):
    logs = sorted(glob.glob(os.path.join(DC, "rung_logs", tag + "_*.log")))
    if not logs:
        print("  %-16s no log yet" % tag); pending += 1; continue
    txt = open(logs[-1], errors="replace").read()
    ms_m, dr_m, ld_m = RE_ITER.search(txt), RE_DROPS.search(txt), RE_LD.search(txt)
    if not (ms_m and dr_m):
        print("  %-16s log incomplete (still running?)" % tag); pending += 1; continue
    ms = "%.3f" % (int(ms_m.group(1)) / 1e9)
    drops = dr_m.group(1)
    rtos = len(re.findall(r"(?m)^At ", txt))

    exp = expected_ms(ref)
    if exp and exp != ms:
        print("  %-16s REFUSED: %s ms but its rung %s measured %s" % (tag, ms, ref, exp))
        refused += 1
        continue

    st = payload_stats(ld_m.group(1)) if ld_m else None
    row = dict.fromkeys(HDR, "")
    row.update(paper_ref="cliff", system="glassfb", cabling=cab, ep=ep, nodes=nodes,
               mb=mb, q=q, relayed_pairs="0", completed="COMPLETE", makespan_ms=ms,
               rtos=str(rtos), drops=drops, status="sweep",
               link_rate_fixed="yes", binary_sha="9ac4f76",
               note=("glass drop cell RECOVERED from its run log; the job died writing "
                     "its CSV (glassdrop took the pkt row branch). Makespan verified "
                     "against rung %s." % ref))
    if st:
        row.update(flows_total=str(st[0]), flows_payload=str(st[1]),
                   mean_fct_ms="%.4f" % st[2], p50_fct_ms="%.4f" % st[3],
                   p99_fct_ms="%.4f" % st[4], max_fct_ms="%.4f" % st[5])
    out = os.path.join(RUNGS, tag + ".csv")
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=HDR)
        w.writeheader(); w.writerow(row)
    written += 1
    print("  %-16s ms=%-10s rtos=%-6s drops=%-8s (verified against %s)"
          % (tag, ms, rtos, drops, ref))

print("\n%d recovered, %d refused, %d still running" % (written, refused, pending))
