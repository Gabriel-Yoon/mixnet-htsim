#!/usr/bin/env python3
"""Fig 1 (motivation): the expert all-to-all's share of the training iteration on the two
incumbents, per EP, from the critical-path walk (decomp_critpath.csv: expert_a2a_ms / makespan_ms)
of the quoted packet-level rows (cliff_all.csv quotable rows; NVL72 = nvl64_pkt_s1). The 8-GPU
island crosses its domain at every EP; NVL72 only at EP=128.

Env: PAPER_RES (default experiments/results/paper), OUT (default .).
"""
import csv, os, re, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
try:
    sys.path.insert(0, os.path.dirname(__file__)); import paper_style as _ps; _ps.apply()
except Exception:
    pass

RES = os.environ.get("PAPER_RES", os.path.join(os.path.dirname(__file__), "..", "..", "experiments", "results", "paper"))
OUT = os.environ.get("OUT", ".")
SYS = [("hgx8_pkt", "HGX-8 (8-GPU island)", "#c46a4a"), ("nvl64_pkt_s1", "NVL72 (64-GPU domain)", "#4b3f8f")]
EPS = [16, 32, 64, 128]
MODEL = {16: "LLaMA-MoE", 32: "LLaMA-MoE", 64: "Qwen-MoE", 128: "Arctic"}

quoted = {}
for r in csv.DictReader(open(os.path.join(RES, "cliff_all.csv"))):
    if (r.get("quotable") or "").lower() == "yes" and r.get("link_rate_fixed") == "yes" and int(float(r["mb"] or 8)) == 8:
        quoted[(r["system"], int(float(r["ep"])))] = float(r["makespan_ms"])
dec = list(csv.DictReader(open(os.path.join(RES, "decomp_critpath.csv"))))
share = {}
for sysname, _, _ in SYS:
    for ep in EPS:
        mk = quoted.get((sysname, ep))
        if mk is None: continue
        c = [x for x in dec if x["label"].startswith(f"{sysname} EP={ep}") and abs(float(x["makespan_ms"]) - mk) < 0.05]
        if not c: continue
        share[(sysname, ep)] = 100 * float(c[0]["expert_a2a_ms"]) / float(c[0]["makespan_ms"])

fig, ax = plt.subplots(figsize=(3.45, 1.9), dpi=200)
w = 0.36
for j, (sysname, name, col) in enumerate(SYS):
    for i, ep in enumerate(EPS):
        v = share.get((sysname, ep))
        if v is None: continue
        x = i + (j - 0.5) * w
        ax.bar(x, v, w * 0.9, color=col, label=name if i == 0 else None, zorder=3)
        ax.text(x, v + 1.5, "%.0f%%" % v, ha="center", va="bottom", fontsize=6.2, color="#333")
ax.axhspan(33, 56, color="#999", alpha=0.12, lw=0, zorder=1)
ax.text(3.72, 44.5, "prior\nfabric\nstudies\n33–56%", fontsize=5.4, color="#666", ha="left", va="center")
ax.set_xlim(-0.55, 4.25)
ax.set_xticks(range(len(EPS))); ax.set_xticklabels([f"EP={e}\n{MODEL[e]}" for e in EPS], fontsize=6.5)
ax.set_ylim(0, 100); ax.set_ylabel("expert A2A share of\niteration (%)", fontsize=7)
ax.tick_params(axis="y", labelsize=6.5)
ax.legend(frameon=False, fontsize=6.2, loc="upper left", handlelength=1.2)
ax.spines["top"].set_visible(False); ax.spines["right"].set_visible(False)
ax.grid(axis="y", lw=0.4, alpha=0.4, zorder=0)
fig.tight_layout(pad=0.3)
for ext in ("png", "pdf"):
    fig.savefig(os.path.join(OUT, f"fig_phases.{ext}"))
for k, v in sorted(share.items()): print("  %-12s EP=%3d  A2A %.1f%%" % (k[0], k[1], v))
print("wrote fig_phases.png")
