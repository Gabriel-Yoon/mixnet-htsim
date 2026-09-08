#!/usr/bin/env python3
"""medium_ablation.csv -- the copper arm against glass, derived from cliff_postfix.csv.

A SEPARATE FILE FROM panel_dse.csv, deliberately. panel_dse.csv answers "what panel
SIZE and what intra-panel TOPOLOGY", comparing 4x4 against 8x8 butterfly and 8x8
mesh. This answers "what MEDIUM", on the 4x4 panel only, holding size and topology
fixed. Putting both in one file would invite a reader to compare an 8x8 mesh row
against a 4x4 copper row, which is two changes at once and answers nothing.

EVERY RUNG IS EMITTED, for the reason the 8x8 arms established: the quoted rungs of
two arms need not sit at the same buffer, and at EP=64 they do not -- glass quotes
at q=8533 and copper at q=4267. `quotable` marks the rule's selection; the matched
comparison is what the figure should use.

Derived from cliff_postfix.csv so collect_rungs remains the single authority on
which rung is quoted; this adds only the arm label and the medium's knob values.
"""
import csv, os

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
SRC = os.path.join(ROOT, "experiments/results/paper/cliff_postfix.csv")
OUT = os.path.join(ROOT, "experiments/results/paper/medium_ablation.csv")

# system -> (arm, long-link medium, GB/s, latency pad ns)
ARM = {"glassfb_800": ("glass", "optical", "384", "300"),
       "copper_fb":   ("copper", "copper",  "100", "400")}
DESIGN_WALK = {"g16b800", "g32b800", "g64b800", "cu16", "cu32", "cu64"}

FIELDS = ["paper_ref", "arm", "grid", "long_link_medium", "long_link_GBps",
          "long_link_lat_ns", "elec_GBps", "port_GBps", "ep", "nodes", "mb", "cabling",
          "walk", "q", "q_over_bdp", "makespan_ms", "rtos", "drops", "quotable",
          "quotable_why", "link_rate_fixed", "binary_sha", "source", "note"]

NOTE = ("medium ablation on the paper's own 4x4 flattened butterfly: ONLY the distance->=2 "
        "intra-panel links change (384->100 GB/s, pad 300->400 ns). Electrical tier 1800 "
        "GB/s, ports 800 GB/s, placement, cabling and routing all unchanged. The 400 ns is "
        "a MODEL PAD raised from a model pad, not a measured copper propagation delay. "
        "Every rung is present; quotable marks the first zero-timeout rung. At EP=64 the "
        "two arms quote at DIFFERENT buffers (glass 8533, copper 4267), so compare at "
        "matched q as well.")

out = []
for r in csv.DictReader(open(SRC)):
    a = ARM.get((r.get("system") or "").strip())
    if not a or (r.get("walk") or "").strip() not in DESIGN_WALK:
        continue
    if not (r.get("makespan_ms") or "").strip():
        continue
    if (r.get("status") or "").strip() != "sweep" or (r.get("relayed_pairs") or "0") not in ("", "0"):
        continue
    if (r.get("ep") or "") not in ("16", "32", "64"):
        continue
    out.append({"paper_ref": "medium_ablation", "arm": a[0], "grid": "4x4",
                "long_link_medium": a[1], "long_link_GBps": a[2], "long_link_lat_ns": a[3],
                "elec_GBps": "1800", "port_GBps": "800",
                "ep": r.get("ep", ""), "nodes": r.get("nodes", ""), "mb": r.get("mb", ""),
                "cabling": r.get("cabling", ""), "walk": r.get("walk", ""),
                "q": r.get("q", ""), "q_over_bdp": r.get("q_over_bdp", ""),
                "makespan_ms": r.get("makespan_ms", ""), "rtos": r.get("rtos", ""),
                "drops": r.get("drops", ""), "quotable": r.get("quotable", ""),
                "quotable_why": r.get("quotable_why", ""),
                "link_rate_fixed": r.get("link_rate_fixed", ""),
                "binary_sha": r.get("binary_sha", ""),
                "source": "cliff_postfix.csv", "note": NOTE})

out.sort(key=lambda r: (int(r["ep"]), r["arm"], float(r["q"] or 0)))
with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=FIELDS); w.writeheader(); w.writerows(out)
print("wrote %s: %d row(s)" % (OUT, len(out)))

q = {(r["ep"], r["arm"]): r for r in out if r["quotable"] == "yes"}
print("\n%-5s %-24s %-24s %s" % ("EP", "glass (quoted)", "copper (quoted)", "same rung?"))
for ep in ("16", "32", "64"):
    g, c = q.get((ep, "glass")), q.get((ep, "copper"))
    if not g or not c:
        print("%-5s incomplete" % ep); continue
    print("%-5s %8s ms @ q=%-8s %8s ms @ q=%-8s %s"
          % (ep, g["makespan_ms"], g["q"], c["makespan_ms"], c["q"],
             "yes" if g["q"] == c["q"] else "NO -- compare at matched q"))
