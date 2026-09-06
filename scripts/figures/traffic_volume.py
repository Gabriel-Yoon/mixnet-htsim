#!/usr/bin/env python3
"""Figure-2 style: per-iteration network traffic volume by parallelism type (DP/TP/EP/PP)
for SOTA MoE models under different parallelism strategies (cf. MixNet SIGCOMM'25 Fig.2).

Analytical (no simulation). All volumes are TOTAL bytes moved on the network per training
iteration; bf16 activations/gradients (2 B). Formulas (first-order, documented):

  T = global tokens = global_batch * seq ;  per-dp tokens t = T/dp
  TP  (all-reduce, 2 fwd + 2 bwd per layer, ring factor 2(tp-1)):
        TP  = L * 4 * 2(tp-1) * T * H * 2
  EP  (all-to-all dispatch+combine, 2 fwd + 2 bwd per layer, cross-rank (ep-1)/ep):
        EP  = L * 4 * (ep-1)/ep * T * topk * H * 2
  DP  (gradient all-reduce once/iter, ring factor 2(dp-1)):
        DP  = 2(dp-1) * P * 2          (P = total params; tp/ep sharding cancels)
  PP  (point-to-point activation across (pp-1) stage boundaries, fwd+bwd):
        PP  = 2 * (pp-1) * T * H * 2

  P (total params) ~ L * (attn 4H^2  +  experts * 3 * H * ffn)   (+ embeddings, ignored)
"""
import os
from collections import OrderedDict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = os.environ.get("FP", "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots")
os.makedirs(FP, exist_ok=True)

# MixNet (SIGCOMM'25) three-model set. H hidden, L layers, ffn expert-hidden, E experts, K topk
MODELS = OrderedDict([
    ("Mixtral-8x7B",   dict(H=4096, L=32, ffn=14336, E=8,  K=2)),
    ("LLaMA-MoE-6.7B", dict(H=4096, L=32, ffn=1376,  E=8,  K=2)),
    ("Qwen-MoE-14.3B", dict(H=2048, L=24, ffn=1408,  E=60, K=4)),
])

BYTES = 2  # bf16
SEQ = 4096
GLOBAL_BATCH = 256  # sequences per iteration (global)

def params(m):
    attn = 4 * m["H"]**2
    experts = m["E"] * 3 * m["H"] * m["ffn"]
    return m["L"] * (attn + experts)

def traffic(m, dp, tp, ep, pp):
    H, L, K = m["H"], m["L"], m["K"]
    T = GLOBAL_BATCH * SEQ
    P = params(m)
    TP = L * 4 * 2*(tp-1)        * T * H * BYTES        if tp > 1 else 0
    EP = L * 4 * (ep-1)/ep       * T * K * H * BYTES    if ep > 1 else 0
    DP = 2*(dp-1) * P * BYTES                            if dp > 1 else 0
    PP = 2 * (pp-1) * T * H * BYTES                      if pp > 1 else 0
    return dict(TP=TP, EP=EP, DP=DP, PP=PP)

# parallelism strategies (each ~128-256 GPU), labeled by what they lean on
STRATS = OrderedDict([
    ("TP-heavy",  lambda E: dict(dp=2, tp=8,  ep=min(8, E),  pp=1)),
    ("EP-heavy",  lambda E: dict(dp=1, tp=1,  ep=E,          pp=1)),
    ("TP+EP",     lambda E: dict(dp=1, tp=8,  ep=min(16, E), pp=1)),
    ("EP+PP",     lambda E: dict(dp=1, tp=1,  ep=min(64, E), pp=2)),
])

GB = 1e9
COL = OrderedDict([("TP", "#2c7fb8"), ("EP", "#d95f0e"), ("DP", "#41ab5d"), ("PP", "#999999")])

# ---- figure: models x strategies, stacked by traffic type ----
fig, axes = plt.subplots(1, len(MODELS), figsize=(14, 5), sharey=False)
for ax, (name, m) in zip(axes, MODELS.items()):
    labels = list(STRATS)
    x = np.arange(len(labels))
    bottoms = np.zeros(len(labels))
    for tkey, col in COL.items():
        vals = []
        for s in labels:
            cfg = STRATS[s](m["E"])
            vals.append(traffic(m, **cfg)[tkey] / GB)
        ax.bar(x, vals, 0.6, bottom=bottoms, color=col, label=tkey)
        bottoms += np.array(vals)
    ax.set_xticks(x); ax.set_xticklabels(labels, rotation=20, fontsize=8)
    ax.set_title(f"{name}\n(E={m['E']}, top-{m['K']}, L={m['L']})", fontsize=9)
    ax.set_ylabel("traffic volume / iter (GB)")
    ax.grid(axis="y", ls=":", alpha=0.5)
axes[-1].legend(fontsize=9, title="parallelism")
fig.suptitle(f"Per-iteration network traffic by parallelism type "
             f"(global batch {GLOBAL_BATCH} x seq {SEQ}, bf16)", fontsize=11)
fig.tight_layout(rect=[0, 0, 1, 0.96])
fig.savefig(f"{FP}/traffic_volume_by_parallelism.png", dpi=150)
print("wrote traffic_volume_by_parallelism.png")

# ---- table ----
print(f"\n{'model':14} {'strategy':9} {'dp/tp/ep/pp':14}  {'TP':>8} {'EP':>8} {'DP':>8} {'PP':>8}  (GB/iter)")
for name, m in MODELS.items():
    for s in STRATS:
        cfg = STRATS[s](m["E"]); tv = traffic(m, **cfg)
        cfgs = f"{cfg['dp']}/{cfg['tp']}/{cfg['ep']}/{cfg['pp']}"
        print(f"{name:14} {s:9} {cfgs:14}  {tv['TP']/GB:8.1f} {tv['EP']/GB:8.1f} "
              f"{tv['DP']/GB:8.1f} {tv['PP']/GB:8.1f}")
