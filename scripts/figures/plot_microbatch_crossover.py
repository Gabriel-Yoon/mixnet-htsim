#!/usr/bin/env python3
"""Microbatch (a2a-load) crossover: glass-FB vs electrical baselines as the per-step a2a volume
grows with microbatch. Reads the new-format sweep CSVs (model,nodes,ep,microbatch,topology,
link_gbps,makespan_ps,makespan_ms) -- one per TAG -- and draws makespan vs microbatch, one line
per topology, per model. The point of the figure: glass-FB (high link BW, limited 4x4-panel
bisection) wins at small microbatch (light a2a) and is overtaken once heavy a2a saturates the
panel bisection. glass_fb is BW-independent (recorded at link_gbps=4096); electrical baselines are
shown at their strongest swept BW (default 800 Gbps)."""
import csv, glob, os
from collections import defaultdict
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
ELEC_BW = int(os.environ.get("ELEC_BW", "800"))          # which electrical link BW to draw
COL = {"fattree":"#d95f0e","os_fattree":"#fdae61","flat":"#41ab5d","mixnet":"#7a0177","glass_fb":"#2c7fb8"}
LAB = {"fattree":f"Fat-tree @{ELEC_BW}Gb","os_fattree":f"Oversub. FT @{ELEC_BW}Gb",
       "flat":f"flat/full-bisect @{ELEC_BW}Gb","mixnet":f"MixNet @{ELEC_BW}Gb",
       "glass_fb":"Glass-FB (design BW)"}

rows = []
for f in sorted(glob.glob(f"{FP}/mixnet_baselines_*.csv")):
    rows += list(csv.DictReader(open(f)))
# model -> topology -> {mb: ms}
data = defaultdict(lambda: defaultdict(dict))
for r in rows:
    if "microbatch" not in r or not r.get("makespan_ms"): continue
    ms = float(r["makespan_ms"])
    if ms <= 0: continue                                  # skip crashes (0)
    bw = int(r["link_gbps"]); topo = r["topology"]
    if topo != "glass_fb" and bw != ELEC_BW: continue     # one electrical BW; glass is BW-independent
    data[r["model"]][topo][int(r["microbatch"])] = ms

models = [m for m in data if any(len(d) > 1 for d in data[m].values())]
if not models: models = list(data)
fig, axes = plt.subplots(1, len(models), figsize=(6.2*len(models), 5.0), squeeze=False)
for ax, model in zip(axes[0], models):
    md = data[model]
    for topo in ["fattree","os_fattree","flat","mixnet","glass_fb"]:
        if topo not in md: continue
        xs = sorted(md[topo]); ys = [md[topo][x] for x in xs]
        style = "o-" if topo != "glass_fb" else "D-"
        lw = 3 if topo == "glass_fb" else 1.8
        ax.plot(xs, ys, style, color=COL.get(topo,"#888"), lw=lw,
                ms=9 if topo=="glass_fb" else 6, label=LAB.get(topo,topo),
                zorder=5 if topo=="glass_fb" else 2)
    # shade where glass wins vs fattree
    if "glass_fb" in md and "fattree" in md:
        xs = sorted(set(md["glass_fb"]) & set(md["fattree"]))
        win = [x for x in xs if md["glass_fb"][x] < md["fattree"][x]]
        if win:
            ax.axvspan(min(win)*0.9, max(win)*1.1, color="#2c7fb8", alpha=0.06)
            ax.text(min(win), ax.get_ylim()[1]*0.05, "glass-FB\nwins", color="#225ea8", fontsize=8.5)
    ax.set_xscale("log", base=2); ax.set_xticks(sorted({int(x) for d in md.values() for x in d}))
    ax.get_xaxis().set_major_formatter(matplotlib.ticker.ScalarFormatter())
    ax.set_xlabel("microbatch  (a2a volume per step  →)")
    ax.set_ylabel("iteration time (ms)")
    ax.set_title(f"{model}  (ep{rows and next(r['ep'] for r in rows if r['model']==model)})")
    ax.grid(ls=":", alpha=.5); ax.legend(fontsize=8.5)
fig.suptitle("Microbatch (a2a-load) crossover: glass-FB wins at light a2a, full-bisection wins at heavy a2a",
             fontsize=12)
fig.tight_layout(rect=[0,0,1,0.95])
out = f"{FP}/microbatch_crossover.png"; fig.savefig(out, dpi=150)
print("wrote", out)
for model in models:
    print(f"\n{model}:")
    md = data[model]
    for mb in sorted({x for d in md.values() for x in d}):
        g = md.get("glass_fb",{}).get(mb); ft = md.get("fattree",{}).get(mb); fl = md.get("flat",{}).get(mb)
        tag = "WIN " if (g and ft and g<ft) else "lose"
        print(f"  mb{mb:<3} glass={g}  fattree={ft}  flat={fl}  [{tag} vs fattree]")
