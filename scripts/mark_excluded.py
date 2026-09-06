#!/usr/bin/env python3
"""Mark the measured-attention Mixtral graph excluded from the paper set (E43).

Resolved by the peer session from its working tree: the L32 graph's output CSV
(paper_topo_compare.csv) never existed, htsim_topo_compare.sh was never run to
completion, and fig_phases' normaliser came from L4 analytical graphs (settled by
magnitude -- L32 seq4096 is ~30x the compute of L4 seq1024, so its makespan would
be seconds, not the 196-233 ms in the figure CSV). Nothing depends on it.
"""
import json, os

RES = "/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results"
TARGET = "mixtral8x7B_paper_dp2tp4pp4_ep8top2_L32_seq4096_mb8_H100"

p = os.path.join(RES, TARGET + ".meta")
meta = json.load(open(p))
meta["excluded"] = True
meta["excluded_reason"] = (
    "measured attention (every other paper graph is analytical) AND deprecated "
    "dp2tp4pp4 config, superseded by dp2tp2pp8 per profile_papercfg_sweep.sh:15. "
    "No figure depends on it: its output CSV never existed and fig_phases' "
    "normaliser came from L4 analytical graphs."
)
meta["excluded_by"] = "E43 / docs/paper_todo.md"
json.dump(meta, open(p, "w"), indent=2)
print("marked excluded:", TARGET)

# Report what the paper set now looks like, so A37's claim is checkable.
inc, exc, unk = [], [], []
for f in sorted(os.listdir(RES)):
    if not f.endswith(".meta"):
        continue
    m = json.load(open(os.path.join(RES, f)))
    if m.get("excluded"):
        exc.append((m["graph"], m["attention_mode"]))
    elif m["attention_mode"] == "analytical":
        inc.append((m["graph"], m["attention_mode"]))
    else:
        unk.append((m["graph"], m["attention_mode"]))

print(f"\nincluded, analytical : {len(inc)}")
print(f"excluded             : {len(exc)}")
for g, m in exc:
    print(f"    {g}  ({m})")
print(f"not analytical & not excluded : {len(unk)}")
for g, m in unk:
    print(f"    {g}  ({m})")
print("\nA37 is TRUE over the included set."
      if not unk else
      "\nA37 still has exceptions in the included set -- resolve before writing it.")
