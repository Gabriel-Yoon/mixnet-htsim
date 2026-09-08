"""Copper vs glass at MATCHED buffer, not only at the quoted rung.

Same lesson as the 8x8 arms: each walk's quoted rung is chosen independently by the
vanishing-timeout rule, so the two arms can quote at different buffers -- and at
EP=64 they do, glass at q=8533 and copper at q=4267. Comparing those two rows
answers a different question from comparing the fabrics, because buffer is the
swept axis. Both views are printed; the matched one is the controlled comparison.
"""
import csv, glob, os, collections

D = ("/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
     "/experiments/results/paper/rungs")

def load(prefix, ep):
    out = {}
    for f in glob.glob(os.path.join(D, "%s_q*.csv" % prefix)):
        q = int(os.path.basename(f).rsplit("_q", 1)[1][:-4])
        for r in csv.DictReader(open(f)):
            if (r.get("makespan_ms") or "") and r.get("status") == "sweep" \
               and (r.get("relayed_pairs") or "0") in ("", "0"):
                out[q] = r
    return out

PAIRS = {16: ("g16b800", "cu16"), 32: ("g32b800", "cu32"), 64: ("g64b800", "cu64")}

for ep in (16, 32, 64):
    gp, cp = PAIRS[ep]
    g, c = load(gp, ep), load(cp, ep)
    print("\n=== EP=%d   glass %s vs copper %s ===" % (ep, gp, cp))
    print("%-8s | %-11s %-8s %-10s | %-11s %-8s %-10s | %s"
          % ("q", "glass ms", "rtos", "drops", "copper ms", "rtos", "drops", "copper/glass"))
    for q in sorted(set(g) & set(c)):
        gm, cm = float(g[q]["makespan_ms"]), float(c[q]["makespan_ms"])
        print("%-8d | %-11.3f %-8s %-10s | %-11.3f %-8s %-10s | %+7.1f%%"
              % (q, gm, g[q]["rtos"], g[q].get("drops", ""),
                 cm, c[q]["rtos"], c[q].get("drops", ""), 100.0 * (cm - gm) / gm))
    only = sorted(set(g) ^ set(c))
    if only:
        print("  buffers present in only one arm: %s" % only)

print("\n=== quoted rungs (each arm's own first zero-timeout rung) ===")
for ep in (16, 32, 64):
    gp, cp = PAIRS[ep]
    g, c = load(gp, ep), load(cp, ep)
    gq = min((q for q in g if g[q]["rtos"] == "0"), default=None)
    cq = min((q for q in c if c[q]["rtos"] == "0"), default=None)
    if gq is None or cq is None:
        print("EP=%-4d incomplete" % ep); continue
    gm, cm = float(g[gq]["makespan_ms"]), float(c[cq]["makespan_ms"])
    print("EP=%-4d glass %8.3f @ q=%-6d   copper %8.3f @ q=%-6d   %s"
          % (ep, gm, gq, cm, cq,
             "same rung" if gq == cq else "DIFFERENT rungs -- not a controlled comparison"))
