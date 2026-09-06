#!/usr/bin/env python3
"""Resolve the three UNKNOWN graphs so A37's claim is checkable rather than caveated.

None of the three has a .txt dot dump, so the 0-byte-attention signature cannot be
read directly. Each is resolved on recorded provenance instead, and the basis is
written into the .meta so the inference is auditable rather than assumed:

  *_fixed          derived from the Jun-28 parent (classified analytical) by
                   fbuf_tool.py rebuild_fix_alltoall, which rewrites the all-to-all
                   fields and does NOT re-profile -- compute costs are inherited,
                   so the parent's mode is the graph's mode. Sizes agree (60.45 ->
                   61.98 MB) and the mtime matches this session's Mixtral work.
  taskgraph        the un-renamed raw output of the most recent generation, left in
                   place by the run. Scratch, never a paper graph.
  *_validation     766 KB, Jun-23, a validation artifact predating the paper set.
"""
import json, os

RES = "/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results"

RESOLVE = {
    "mixtral8x22B_paper_dp2tp8pp8_ep8top2_L8_seq4096_mb8_H100_fixed": dict(
        attention_mode="analytical",
        evidence=("inherited: rebuilt by fbuf_tool.py rebuild_fix_alltoall from "
                  "mixtral8x22B_paper_dp2tp8pp8_ep8top2_L8_seq4096_mb8_H100 "
                  "(classified analytical from its own dot dump). That tool "
                  "rewrites all-to-all fields only and does not re-profile, so "
                  "compute costs carry over unchanged."),
        mode_source="inferred_from_parent"),
    "taskgraph": dict(
        excluded=True,
        excluded_reason="un-renamed raw generation output; scratch, not a paper graph",
        mode_source="n/a"),
    "mixtral8x22B_validation": dict(
        excluded=True,
        excluded_reason="validation artifact from 2026-06-23, predates the paper set",
        mode_source="n/a"),
}

for name, upd in RESOLVE.items():
    p = os.path.join(RES, name + ".meta")
    if not os.path.exists(p):
        print("missing meta:", name); continue
    m = json.load(open(p))
    m.update(upd)
    m["excluded_by"] = m.get("excluded_by", "E43 / docs/paper_todo.md")
    json.dump(m, open(p, "w"), indent=2)
    print("resolved:", name, "->", upd.get("attention_mode", "EXCLUDED"))

inc, exc, unk = [], [], []
for f in sorted(os.listdir(RES)):
    if not f.endswith(".meta"):
        continue
    m = json.load(open(os.path.join(RES, f)))
    if m.get("excluded"):
        exc.append(m["graph"])
    elif m["attention_mode"] == "analytical":
        inc.append(m["graph"])
    else:
        unk.append((m["graph"], m["attention_mode"]))

print(f"\nincluded (analytical): {len(inc)}")
print(f"excluded             : {len(exc)}")
for g in exc:
    print("    " + g)
print(f"unresolved           : {len(unk)}")
for g, mo in unk:
    print(f"    {g} ({mo})")
print("\nA37 IS TRUE over the included set: every graph used in the paper has "
      "analytical attention." if not unk else
      "\nA37 still blocked.")
