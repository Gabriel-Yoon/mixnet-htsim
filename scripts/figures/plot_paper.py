#!/usr/bin/env python3
"""DATE 2027 figure regeneration from paper_ref CSVs (experiments/results/paper/<paper_ref>.csv).

Schema (see message 9c52d23f): paper_ref, workload_type, ep_source, model, topk, ep, mb, nodes,
system, binary_sha, ..., makespan_ms, compute_cp_ms, rtos, mean_fct_ms, p99_fct_ms, max_fct_ms,
status. Only rows with status == final are drawn. Every figure prints the rows it used.

  python3 plot_paper.py cliff   -> fig_cliff.png       (Fig 6a: iteration vs EP, per system)
  python3 plot_paper.py decomp  -> fig_decomp.png      (Fig 6b: EP=32 gap decomposition)
  python3 plot_paper.py beyond  -> fig_beyond.png      (Fig 6c: EP=128 training + serving check)
  python3 plot_paper.py mb      -> fig_mb.png          (Fig 7a-ish: iteration vs mb, glass vs nvl64)
  python3 plot_paper.py ladder  -> fig_ladder.png      (Fig 7c: Glass-A..D + copper-FB)
  python3 plot_paper.py energy  -> fig_energy.png      (Fig 7b: GB/s/W + energy/iter, both pJ/bit ends)
  python3 plot_paper.py all
Env: PAPER_RES (default experiments/results/paper), OUT (default .).
"""
import csv, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

RES = os.environ.get("PAPER_RES", os.path.join(os.path.dirname(__file__), "..", "..", "experiments", "results", "paper"))
OUT = os.environ.get("OUT", ".")
SYS_LABEL = {"glassfb": "Glass-FB", "hgx8": "HGX-8", "nvl64": "NVL-64", "flat900_capped": "900 GB/s no-boundary bound",
             "flat900_uncapped": "900 GB/s uncapped", "copperfb": "Copper-FB @100",
             "glass_A": "A: as submitted", "glass_B": "B: +placement", "glass_C": "C: +16-port cabling",
             "glassfb_mesh": "Glass-FB (4-edge mesh)", "glassfb_hier": "Glass-FB (hier. A2A)", "nvl64_pkt": "NVL-64 (packet-level)", "hgx8_pkt": "HGX-8 (packet-level)"}
SYS_COLOR = {"glassfb": "#1f6f8b", "glassfb_mesh": "#7fb3c8", "glassfb_hier": "#0b3d4f", "hgx8": "#d95f0e", "hgx8_pkt": "#d95f0e", "nvl64": "#7a0177", "nvl64_pkt": "#7a0177", "flat900_capped": "#7a0177",
             "flat900_uncapped": "#b8a0c8", "copperfb": "#8c6d31"}

def load(ref):
    p = os.path.join(RES, f"{ref}.csv")
    if not os.path.exists(p):
        sys.exit(f"missing {p} (paper_ref={ref} rows have not landed)")
    rows = [r for r in csv.DictReader(open(p)) if r.get("status", "final") == "final"]
    if not rows:
        sys.exit(f"{p}: no rows with status=final")
    for r in rows:
        for k in ("ep", "mb", "nodes", "rtos"):
            if r.get(k): r[k] = int(float(r[k]))
        for k in ("makespan_ms", "compute_cp_ms", "mean_fct_ms", "p99_fct_ms", "max_fct_ms"):
            if r.get(k): r[k] = float(r[k])
    print(f"[{ref}] {len(rows)} final rows:", ", ".join(sorted({f"{r['system']}@EP{r.get('ep')}" for r in rows})))
    return rows

def f(name):
    return os.path.join(OUT, name)

def cliff():
    rows = load("cliff")
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    for sysname in ("hgx8", "hgx8_pkt", "nvl64", "nvl64_pkt", "glassfb_mesh", "glassfb", "glassfb_hier"):
        pts = sorted([(r["ep"], r["makespan_ms"], r) for r in rows if r["system"] == sysname])
        if not pts: continue
        dashed = sysname in ("hgx8", "nvl64")  # analytic island = vendor-claim upper bound
        ax.plot([p[0] for p in pts], [p[1] for p in pts], "--" if dashed else "o-", color=SYS_COLOR[sysname],
                label=SYS_LABEL[sysname] + (" (vendor-claim bound)" if dashed else ""), lw=1.2 if dashed else 1.5, ms=4, alpha=0.8 if dashed else 1)
        for ep, y, r in pts:
            if r.get("rtos") and r["rtos"] > 0:
                ax.annotate(f"{r['rtos']:,} RTO", (ep, y), fontsize=5, textcoords="offset points", xytext=(3, 3))
    # model per point
    models = {}
    for r in rows: models.setdefault(r["ep"], set()).add(f"{r['model']} top-{r.get('topk','?')}")
    ax.set_xscale("log", base=2); ax.set_xticks(sorted(models)); ax.set_xticklabels([f"{ep}\n{'/'.join(sorted(models[ep]))}" for ep in sorted(models)], fontsize=5.5)
    ax.set_yscale("log"); ax.set_ylabel("iteration (ms)", fontsize=7); ax.set_xlabel("EP degree (model per point)", fontsize=7)
    ax.axvline(16, color="#1f6f8b", ls=":", lw=0.8); ax.axvline(8, color="#d95f0e", ls=":", lw=0.8); ax.axvline(64, color="#7a0177", ls=":", lw=0.8)
    ax.tick_params(labelsize=6); ax.legend(fontsize=5.5, frameon=False); ax.grid(alpha=0.3, which="both")
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_cliff.png")); print("wrote fig_cliff.png")

def decomp():
    rows = [r for r in load("decomp")]
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    systems = sorted({r["system"] for r in rows}, key=lambda s: list(SYS_LABEL).index(s) if s in SYS_LABEL else 99)
    comps = [c for c in ("a2a_ms", "dp_allreduce_ms", "pp_ms", "compute_ms", "other_ms") if any(r.get(c) for r in rows)]
    bottoms = [0] * len(systems)
    for c in comps:
        vals = [float(next(r for r in rows if r["system"] == s).get(c) or 0) for s in systems]
        ax.bar([SYS_LABEL.get(s, s) for s in systems], vals, bottom=bottoms, label=c.replace("_ms", ""), width=0.6)
        bottoms = [b + v for b, v in zip(bottoms, vals)]
    ax.set_ylabel("EP=32 iteration (ms)", fontsize=7); ax.tick_params(labelsize=6); ax.legend(fontsize=5.5, frameon=False)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_decomp.png")); print("wrote fig_decomp.png")

def beyond():
    rows = load("beyond")
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    groups = sorted({(r["workload_type"], r["ep"], r.get("model")) for r in rows})
    x = 0; ticks = []; labels = []
    for wt, ep, model in groups:
        sub = [r for r in rows if (r["workload_type"], r["ep"], r.get("model")) == (wt, ep, model)]
        g = next((r["makespan_ms"] for r in sub if r["system"] == "glassfb"), None)
        for r in sorted(sub, key=lambda r: list(SYS_LABEL).index(r["system"]) if r["system"] in SYS_LABEL else 99):
            ax.bar(x, r["makespan_ms"] / g if g else r["makespan_ms"], color=SYS_COLOR.get(r["system"], "#999"), width=0.8)
            ax.text(x, (r["makespan_ms"] / g if g else r["makespan_ms"]) * 1.02, f"{r['makespan_ms']:.0f}", ha="center", fontsize=5)
            ticks.append(x); labels.append(SYS_LABEL.get(r["system"], r["system"]).split(":")[0]); x += 1
        x += 0.8
    ax.set_xticks(ticks); ax.set_xticklabels(labels, rotation=60, fontsize=5.5, ha="right")
    ax.set_ylabel("normalized to Glass-FB (ms labelled)", fontsize=7); ax.tick_params(labelsize=6)
    ax.set_title(" | ".join(f"{wt} EP{ep} {m}" for wt, ep, m in groups), fontsize=6)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_beyond.png")); print("wrote fig_beyond.png")

def mb():
    rows = load("mb") + [r for r in (load("load") if os.path.exists(os.path.join(RES, "load.csv")) else [])]
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    for (sysname, model), style in {("glassfb", "llamaMoE"): "o-", ("nvl64", "llamaMoE"): "s--", ("glassfb", "dbrx"): "o:", ("nvl64", "dbrx"): "s-."}.items():
        pts = sorted([(r["mb"], r["makespan_ms"]) for r in rows if r["system"] == sysname and r.get("model") == model])
        if pts: ax.plot([p[0] for p in pts], [p[1] for p in pts], style, color=SYS_COLOR[sysname], label=f"{SYS_LABEL[sysname]} {model}", lw=1.3, ms=4)
    ax.set_xscale("log", base=2); ax.set_xticks([4, 8, 16, 32]); ax.set_xticklabels([4, 8, 16, 32])
    ax.set_xlabel("microbatch (EP=16)", fontsize=7); ax.set_ylabel("iteration (ms)", fontsize=7); ax.tick_params(labelsize=6)
    ax.legend(fontsize=5.5, frameon=False); ax.grid(alpha=0.3)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_mb.png")); print("wrote fig_mb.png")

def ladder():
    rows = load("ladder")
    order = ["glass_A", "glass_B", "glass_C", "copperfb", "flat900_capped"]
    rows = sorted([r for r in rows if r["system"] in order], key=lambda r: order.index(r["system"]))
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    base = next((r["makespan_ms"] for r in rows if r["system"] == "glass_C"), None)
    for i, r in enumerate(rows):
        ax.bar(i, r["makespan_ms"], color=SYS_COLOR.get(r["system"], "#1f6f8b"), width=0.7)
        ax.text(i, r["makespan_ms"] * 1.02, f"{r['makespan_ms']:.0f}" + (f"\n{r['makespan_ms']/base:.2f}x" if base else ""), ha="center", fontsize=5)
    ax.set_xticks(range(len(rows))); ax.set_xticklabels([SYS_LABEL.get(r["system"], r["system"]) for r in rows], rotation=45, ha="right", fontsize=5.5)
    ax.set_ylabel("EP=16 iteration (ms)", fontsize=7); ax.tick_params(labelsize=6)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_ladder.png")); print("wrote fig_ladder.png")

def energy():
    rows = load("power")
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(3.4, 2.4), dpi=200)
    systems = ["glassfb", "hgx8", "nvl64"]
    for i, s in enumerate(systems):
        sub = [r for r in rows if r["system"] == s]
        if not sub: continue
        e = sorted(float(r["energy_J"]) for r in sub if r.get("energy_J"))
        if e:
            a2.bar(i, e[-1], color=SYS_COLOR[s], alpha=0.35, width=0.6); a2.bar(i, e[0], color=SYS_COLOR[s], width=0.6)
            a2.text(i, e[-1] * 1.02, f"{e[0]:.2g}–{e[-1]:.2g}", ha="center", fontsize=5)
        bw = [float(r["gbps_per_w"]) for r in sub if r.get("gbps_per_w")]
        if bw:
            a1.bar(i, max(bw), color=SYS_COLOR[s], alpha=0.35, width=0.6); a1.bar(i, min(bw), color=SYS_COLOR[s], width=0.6)
            a1.text(i, max(bw) * 1.02, f"{min(bw):.0f}–{max(bw):.0f}", ha="center", fontsize=5)
    for a, yl in ((a1, "cross-domain GB/s per W"), (a2, "interconnect J / iteration (bytes moved)")):
        a.set_xticks(range(len(systems))); a.set_xticklabels([SYS_LABEL[s] for s in systems], fontsize=5.5, rotation=30, ha="right")
        a.set_ylabel(yl, fontsize=6); a.tick_params(labelsize=6)
    fig.suptitle("dark = favourable pJ/bit end, light = conservative end", fontsize=6)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_energy.png")); print("wrote fig_energy.png")

if __name__ == "__main__":
    which = sys.argv[1:] or ["all"]
    fns = {"cliff": cliff, "decomp": decomp, "beyond": beyond, "mb": mb, "ladder": ladder, "energy": energy}
    for w in (fns if "all" in which else which):
        try: fns[w]()
        except SystemExit as e: print("skip:", e)
