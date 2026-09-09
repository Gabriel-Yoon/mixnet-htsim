"""The panel-size DSE across all three panel sizes, quoted AND at matched buffer.

Three panel sizes x two intra-panel topologies x three EPs. The quoted rungs of
different arms need not sit at the same buffer -- they did not for the 8x8 mesh,
and they do not here -- so the matched view is the controlled comparison and the
quoted view is what the vanishing-timeout rule selects. Both are printed.
"""
import csv, glob, os

D = ("/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
     "/experiments/results/paper/rungs")

# label -> {ep: rung-file prefix}
ARMS = [
    ("4x4  FB  (16 GPU, 384)", {16: "g16b800", 32: "g32b800", 64: "g64b800"}),
    ("8x4  FB  (32 GPU, 192)", {16: "p32_16", 32: "p32_32", 64: "p32_64"}),
    ("8x8  FB  (64 GPU, 128)", {16: "fb64_ep16", 32: "fb64_ep32", 64: "fb64_ep64"}),
    ("8x4  MESH(32 GPU, 192)", {16: "m32_16", 32: "m32_32", 64: "m32_64"}),
    ("8x8  MESH(64 GPU, 128)", {16: "mesh64_ep16", 32: "mesh64_ep32", 64: "mesh64_ep64"}),
]


def load(prefix):
    out = {}
    for f in glob.glob(os.path.join(D, "%s_q*.csv" % prefix)):
        q = int(os.path.basename(f).rsplit("_q", 1)[1][:-4])
        for r in csv.DictReader(open(f)):
            if (r.get("makespan_ms") or "") and r.get("status") == "sweep" \
               and (r.get("relayed_pairs") or "0") in ("", "0"):
                out[q] = r
    return out


print("=" * 100)
print("QUOTED rung of each arm -- first rung with no timeouts (drop-aware branch if none)")
print("=" * 100)
print("%-24s %-24s %-24s %-24s" % ("arm", "EP=16", "EP=32", "EP=64"))
for label, pref in ARMS:
    cells = []
    for ep in (16, 32, 64):
        d = load(pref[ep])
        qq = min((q for q in d if d[q]["rtos"] == "0"), default=None)
        if qq is None:
            qq = min((q for q in d if (d[q].get("drops") or "") == "0"), default=None)
        if qq is None:
            cells.append("  (not quoted)"); continue
        dr = d[qq].get("drops") or "-"
        cells.append("%8s @q%-6s d=%-6s" % (d[qq]["makespan_ms"], qq, dr))
    print("%-24s %-24s %-24s %-24s" % (label, *cells))

print("\n" + "=" * 100)
print("MATCHED buffer -- every arm at the same q. This is the controlled comparison.")
print("=" * 100)
for ep in (16, 32, 64):
    tabs = [(lab, load(p[ep])) for lab, p in ARMS]
    tabs = [(l, t) for l, t in tabs if t]
    if len(tabs) < 2:
        continue
    qs = sorted(set.intersection(*[set(t) for _, t in tabs]))
    print("\n  EP=%d" % ep)
    print("  %-8s %s" % ("q", " ".join("%-21s" % l for l, _ in tabs)))
    for q in qs:
        cells = []
        for _, t in tabs:
            r = t[q]
            cells.append("%9s r=%-4s d=%-5s" % (r["makespan_ms"], r["rtos"],
                                                (r.get("drops") or "-")[:5]))
        print("  %-8d %s" % (q, " ".join("%-21s" % c for c in cells)))

print("\n" + "=" * 100)
print("On the PLATEAU (largest buffer all arms share), relative to the 4x4 design point")
print("=" * 100)
for ep in (16, 32, 64):
    tabs = [(lab, load(p[ep])) for lab, p in ARMS]
    tabs = [(l, t) for l, t in tabs if t]
    qs = sorted(set.intersection(*[set(t) for _, t in tabs]))
    if not qs:
        continue
    q = qs[-1]
    base = float(tabs[0][1][q]["makespan_ms"])
    print("\n  EP=%-4d at q=%d   (4x4 = %.3f ms)" % (ep, q, base))
    for lab, t in tabs:
        m = float(t[q]["makespan_ms"])
        print("    %-24s %9.3f ms   %+7.2f%%" % (lab, m, 100 * (m - base) / base))
