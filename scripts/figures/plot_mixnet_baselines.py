#!/usr/bin/env python3
"""MixNet-paper-style topology comparison plot. Reads mixnet_baselines.csv and draws normalized
iteration time vs link bandwidth (100-800 Gbps), one curve per topology, per model. Auto-adapts:
- if multiple link_gbps per topology -> line curves (the full HPC sweep);
- if a single BW -> grouped bars (the local preliminary).
Normalized to the FASTEST run per model (1.0 = least time). glass_optical (4096 'Gbps' = 512 GB/s)
is shown as a star off the electrical 100-800 range."""
import csv, os
from collections import defaultdict
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
COL = {"fattree":"#d95f0e","os_fattree":"#fdae61","flat":"#41ab5d","mixnet":"#7a0177",
       "glass":"#9ecae1","glass_fb":"#2c7fb8","glass_optical":"#2c7fb8"}
LAB = {"fattree":"Fat-tree","os_fattree":"Oversub. Fat-tree","flat":"flat (TopoOpt)",
       "mixnet":"MixNet","glass":"Glass-FB (iso-BW)","glass_fb":"Glass-FB (design: elec1800/opt400/inter200)","glass_optical":"Glass-FB"}

rows = list(csv.DictReader(open(f"{FP}/mixnet_baselines.csv")))
models = sorted(set(r["model"] for r in rows))
fig, axes = plt.subplots(1, len(models), figsize=(6.5*len(models), 5.2), squeeze=False)
for ax, model in zip(axes[0], models):
    mr = [r for r in rows if r["model"] == model]
    norm = min(float(r["makespan_ms"]) for r in mr)
    byt = defaultdict(dict)
    for r in mr: byt[r["topology"]][int(r["link_gbps"])] = float(r["makespan_ms"])
    elec = {t: {b:v for b,v in d.items() if b <= 800} for t,d in byt.items()}
    multi_bw = any(len(d) > 1 for d in elec.values())
    if multi_bw:                              # full sweep -> curves
        for t, d in elec.items():
            if not d: continue
            xs = sorted(d); ax.plot(xs, [d[x]/norm for x in xs], "o-", color=COL.get(t,"#888"), label=LAB.get(t,t))
        # Glass-FB design = BW-independent -> horizontal reference line (electrical sweeps toward it)
        for gk in ("glass_fb","glass_optical","glass"):
            if gk in byt:
                v = list(byt[gk].values())[0]/norm
                ax.axhline(v, ls="-.", lw=2.2, color="#2c7fb8",
                           label=f"Glass-FB design (elec1800/opt400/inter200) = {v:.2f}x")
                break
        ax.set_xlabel("link bandwidth (Gbps)"); ax.set_xticks([100,200,400,600,800])
    else:                                     # single BW -> bars
        topos = [t for t in COL if t in byt]
        vals = [list(byt[t].values())[0]/norm for t in topos]
        ax.bar(range(len(topos)), vals, color=[COL[t] for t in topos])
        for i,v in enumerate(vals): ax.text(i, v+.02, f"{v:.2f}", ha="center", fontsize=9)
        ax.set_xticks(range(len(topos))); ax.set_xticklabels([LAB[t] for t in topos], rotation=20, fontsize=8)
        ax.set_xlabel(f"(preliminary: single BW {mr[0]['link_gbps']} Gbps)")
    ax.axhline(1.0, ls=":", color="grey", alpha=.6)
    ax.set_ylabel("normalized iteration time (1.0 = fastest)")
    ax.set_title(f"{model} (ep{mr[0]['ep']})")
    ax.grid(axis="y", ls=":", alpha=.5); ax.legend(fontsize=8)
fig.suptitle("Topology comparison — glass-FB vs MixNet-paper baselines (unified weightmatrix / skewed a2a)", fontsize=12)
fig.tight_layout(rect=[0,0,1,0.96]); fig.savefig(f"{FP}/mixnet_baselines.png", dpi=150)
print("wrote mixnet_baselines.png")
for model in models:
    mr=[r for r in rows if r["model"]==model]; norm=min(float(r["makespan_ms"]) for r in mr)
    for r in sorted(mr, key=lambda r:float(r["makespan_ms"])):
        print(f"  {model} {r['topology']:14} @{r['link_gbps']:>4}Gbps  {float(r['makespan_ms']):6.0f} ms  ({float(r['makespan_ms'])/norm:.2f}x)")
