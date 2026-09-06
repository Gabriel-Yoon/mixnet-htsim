#!/usr/bin/env python3
"""Inter-panel / link-bandwidth DSE with ALL topologies overlaid (llamaMoE, a2a-dominant, 128 GPU).
x = the swept interconnect BW (glass-FB: inter-panel BW with intra fixed 512; fat-tree/fc: per-link BW).
Shows how much inter-panel optical BW glass-FB needs to beat a normal fat-tree and approach the
fully-connected / compute-bound floor."""
import csv, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"
FLOOR = 44.8

# glass-FB: inter-panel BW sweep (intra fixed 512)
glass = {}
for r in csv.DictReader(open(f"{FP}/interpanel_dse.csv")):
    if r["model"] == "llamaMoE": glass[int(r["inter_bw"])] = float(r["makespan_ms"])
# fat-tree: link-BW sweep (50 from a2a CSV, 100/200/512 from isopower)
ft = {50: 245.052}
for r in csv.DictReader(open(f"{FP}/isopower_compare.csv")):
    if r["fabric"] == "fattree": ft[int(r["link_gbps"])] = float(r["makespan_ms"])
# fc: 50 from a2a CSV + 100/200/512 from dse_multitopo
fc = {50: 86.384}
for r in csv.DictReader(open(f"{FP}/dse_multitopo.csv")):
    if r["topology"] == "fc": fc[int(r["link_gbps"])] = float(r["makespan_ms"])

# normalize to the FASTEST observed iteration time (1.0 = least time taken)
NORM = min(list(glass.values()) + list(ft.values()) + list(fc.values()))
def xy(d): xs = sorted(d); return xs, [d[x]/NORM for x in xs]

fig, ax = plt.subplots(figsize=(9, 5.8))
gx, gy = xy(glass); ax.plot(gx, gy, "o-", color="#2c7fb8", lw=2.2, ms=7, label="Glass-FB (sweep inter-panel; intra fixed 512)")
fx, fy = xy(ft);    ax.plot(fx, fy, "s--", color="#d95f0e", lw=2, ms=7, label="Fat-tree (sweep per-link)")
# fc dropped (unreliable: flat ~84ms regardless of BW)
ax.axhline(FLOOR/NORM, ls=":", color="grey", label=f"compute floor ({FLOOR/NORM:.2f}×)")
ax.axhline(1.0, ls="-", color="#41ab5d", alpha=.3)
ax.axvline(50, ls="--", color="#999", alpha=.6); ax.text(52, max(gy)*.8, "IB 50", color="#666", fontsize=8)
ax.axhline(ft[50]/NORM, ls=":", color="#d95f0e", alpha=.35)
ax.annotate("glass-FB beats a normal\nfat-tree(IB 50) once\ninter-panel ≳ 75 GB/s",
            xy=(100, 180/NORM), xytext=(160, 380/NORM), fontsize=8.5, color="#225ea8",
            arrowprops=dict(arrowstyle="->", color="#2c7fb8"))
ax.set_xscale("log"); ax.set_xticks(gx); ax.set_xticklabels([str(x) for x in gx], fontsize=8)
ax.set_xlabel("interconnect bandwidth (GB/s)  —  glass: inter-panel, fat-tree/fc: per-link")
ax.set_ylabel(f"normalized iteration time  (1.0 = fastest = {NORM:.0f} ms)")
ax.set_title("Inter-panel / link-BW DSE across topologies (llamaMoE, a2a-dominant, 128 GPU)\n"
             "normalized to the fastest run; glass-FB needs inter-panel ~300 to reach the fc floor")
ax.legend(fontsize=8.5); ax.grid(ls=":", alpha=.5)
fig.tight_layout(); fig.savefig(f"{FP}/interpanel_dse.png", dpi=150)
print("wrote interpanel_dse.png (multi-topology)")
print(f"  glass crosses fat-tree(50)={ft[50]:.0f} between inter "
      f"{[x for x in gx if glass[x]>ft[50]][-1]} and {[x for x in gx if glass[x]<ft[50]][0]} GB/s")
print(f"  fc floor (flat) ~{min(fc.values()):.0f} ms; glass best {min(gy):.0f}; fat-tree best {min(fy):.0f}")
