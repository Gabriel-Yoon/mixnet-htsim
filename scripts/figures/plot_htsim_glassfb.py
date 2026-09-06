#!/usr/bin/env python3
"""Glass-FB vs NVL72 / Fat-tree / FC, packet-level (mixnet-htsim), NORMALIZED.

Following the MixNet paper (SIGCOMM'25) methodology: compare topologies at the same
link bandwidth against a **non-blocking Fat-tree** reference -- never an infinite-BW
"ideal". Absolute .fbuf compute times are not calibrated to real HW, so we report
RATIOS (speedup), which cancel that miscalibration because compute is identical across
fabric variants (only the network changes).

  (a) microbatch sweep (mixtral8x7b, 64 GPU / 4 panels): glass speedup over NVL72.
  (b) fabric + panel-grid comparison (mixtral8x22b, 128 GPU): speedup over Fat-tree,
      with the non-blocking FC fabric drawn as the realistic upper-bound reference.

All numbers are mixnet-htsim makespans (ms) measured on this machine, 100 Gbps links
for the electrical fabrics; glass intra/inter BW per the glass WG budget (GB/s).
"""
import matplotlib
matplotlib.use("Agg")
import numpy as np
import matplotlib.pyplot as plt

# ---- (a) mixtral8x7b, 64 GPU: glass(512/512) vs NVL72(450/50), per microbatch ----
MB = [8, 16, 32, 64]
GLASS = {8: 1351.9, 16: 1368.0, 32: 1404.5, 64: 1454.6}
NVL   = {8: 1543.8, 16: 1752.6, 32: 2174.1, 64: 2994.2}

# ---- (b) mixtral8x22b, 128 GPU: makespan (ms), normalize to fat-tree ----
FATTREE = 2721.5                       # non-? fat-tree @100Gbps (baseline = 1.0)
FC_REF  = 1302.0                       # fully-connected non-blocking @100Gbps (upper bound)
BARS = [   # (label, makespan_ms, color)
    ("Fat-tree\n(electrical)",       2721.5, "#7f8c8d"),
    ("MixNet\n(optical recfg)",      2637.1, "#e67e22"),
    ("NVL72 4x4\n(NVLink/IB 450/50)", 2142.1, "#c0392b"),
    ("Glass 4x4 graph\n(iso 100/100)", 1706.3, "#85c1e9"),
    ("Glass 6x6\n(256/512)",          1368.4, "#5499c7"),
    ("Glass 4x4\n(512/512)",          1316.3, "#2471a3"),
    ("Glass 8x8\n(128/512)",          1259.1, "#1a5276"),
]

fig, (ax0, ax1) = plt.subplots(1, 2, figsize=(14, 4.6))

# panel (a): glass speedup over NVL72
spd = [NVL[m] / GLASS[m] for m in MB]
ax0.plot(MB, spd, "s-", color="#2471a3", lw=2)
ax0.axhline(1.0, ls="--", color="#c0392b", alpha=0.7)
ax0.annotate("NVL72 (=1.0)", (MB[0], 1.0), textcoords="offset points", xytext=(2, -12),
             fontsize=8, color="#c0392b")
for x, y in zip(MB, spd):
    ax0.annotate(f"{y:.2f}x", (x, y), textcoords="offset points", xytext=(0, 7),
                 fontsize=9, ha="center", color="#2471a3")
ax0.set_xlabel("microbatch (a2a payload / comm intensity)")
ax0.set_ylabel("Glass-FB speedup over NVL72  (T$_{NVL}$/T$_{glass}$)")
ax0.set_xticks(MB)
ax0.set_ylim(0.9, 2.2)
ax0.set_title("(a) Glass vs NVL72, same 2-tier topology\nmixtral8x7b, 64 GPU / 4 panels")
ax0.grid(alpha=0.3)

# panel (b): speedup over fat-tree, bar chart
labels = [b[0] for b in BARS]
spdb = [FATTREE / b[1] for b in BARS]
colors = [b[2] for b in BARS]
x = np.arange(len(labels))
ax1.bar(x, spdb, color=colors)
ax1.axhline(1.0, ls="--", color="#7f8c8d", alpha=0.8)
ax1.axhline(FATTREE / FC_REF, ls=":", color="#27ae60", lw=2)
ax1.annotate(f"FC @100Gbps = {FATTREE/FC_REF:.2f}x (iso-BW topology bound)",
             (len(labels) - 1, FATTREE / FC_REF), textcoords="offset points",
             xytext=(-4, 4), fontsize=8, color="#27ae60", ha="right")
for xi, y in zip(x, spdb):
    ax1.annotate(f"{y:.2f}x", (xi, y), textcoords="offset points", xytext=(0, 3),
                 fontsize=9, ha="center")
ax1.set_xticks(x)
ax1.set_xticklabels(labels, fontsize=8)
ax1.set_ylabel("speedup over Fat-tree  (T$_{fat-tree}$/T)")
ax1.set_ylim(0, 2.5)
ax1.set_title("(b) Fabric & panel-grid vs Fat-tree (=1.0)\nmixtral8x22b, 128 GPU, 100 Gbps electrical")
ax1.grid(alpha=0.3, axis="y")

fig.suptitle("Glass-FB packet-level comparison (mixnet-htsim), normalized -- "
             "MixNet-style: ratios vs Fat-tree, no infinite-BW ideal", fontsize=11)
fig.tight_layout(rect=[0, 0, 1, 0.95])
out = "outputs/paper_figures/S_htsim_glassfb_normalized.png"
fig.savefig(out, dpi=140)
print("wrote", out)
