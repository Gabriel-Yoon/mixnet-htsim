#!/usr/bin/env python3
"""Topology comparison plot: makespan = compute + exposed comm, per topology, per model.
Reads fast_topo_compare.csv (or paper_topo_compare.csv). compute floor from the model's
compute_cp (hardcoded from the measured task graph)."""
import csv, os
from collections import defaultdict, OrderedDict
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = os.environ.get("FP", "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots")
CSV = os.environ.get("CSV", f"{FP}/fast_topo_compare.csv")
COMPUTE = {"mixtral8x7B": 102.0, "llamaMoE": 75.0, "qwenMoE": 70.0}  # compute_cp (ms), measured

mk = defaultdict(dict)
with open(CSV) as f:
    for r in csv.DictReader(f):
        mk[r["model"]][r["topology"]] = float(r["makespan_ms"])

TOPOS = [("fattree","Fat-tree (IB 50 GB/s)","#d95f0e"),
         ("fc","Fully-conn (IB 50 GB/s)","#fdae61"),
         ("glass_optical","Glass-FB optical (512 GB/s)","#2c7fb8"),
         ("glass_atIB","Glass-FB @ IB (50 GB/s)","#9ecae1")]
models = [m for m in COMPUTE if m in mk]

fig, ax = plt.subplots(figsize=(10,5.5))
x = np.arange(len(models)); n=len(TOPOS); bw=0.8/n
for i,(key,lab,col) in enumerate(TOPOS):
    comp=[COMPUTE[m] for m in models]
    exp=[max(0.0, mk[m].get(key,COMPUTE[m])-COMPUTE[m]) for m in models]
    xs=x+(i-(n-1)/2)*bw
    ax.bar(xs,comp,bw,color=col,alpha=0.35)
    ax.bar(xs,exp,bw,bottom=comp,color=col,label=lab)
    for xi,m in zip(xs,models):
        v=mk[m].get(key);
        if v: ax.text(xi,v+1,f"{v:.0f}",ha="center",fontsize=7)
ax.bar([],[],color="grey",alpha=0.35,label="compute (critical path)")
ax.set_xticks(x); ax.set_xticklabels(models)
ax.set_ylabel("per-layer makespan (ms)")
ax.set_title("Topology comparison — communication time (seq1024, TP8/allreduce-dominant, 128 GPU)\n"
             "glass-optical vs normal-H100 fat-tree/leaf-spine; glass@IB isolates topology")
ax.legend(fontsize=8,loc="upper left"); ax.grid(axis="y",ls=":",alpha=0.5)
fig.tight_layout(); fig.savefig(f"{FP}/topo_compare.png",dpi=150)
print("wrote topo_compare.png")
for m in models:
    ft=mk[m].get("fattree"); g=mk[m].get("glass_optical")
    print(f"  {m}: glass-optical {g:.1f} vs fat-tree {ft:.1f}  -> {ft/g:.2f}x faster")
