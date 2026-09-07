#!/usr/bin/env python3
"""DATE 2027 figure regeneration from paper_ref CSVs (experiments/results/paper/<paper_ref>.csv).

Schema (see message 9c52d23f): paper_ref, workload_type, ep_source, model, topk, ep, mb, nodes,
system, binary_sha, ..., makespan_ms, compute_cp_ms, rtos, mean_fct_ms, p99_fct_ms, max_fct_ms,
status. Only rows with status == final are drawn. Every figure prints the rows it used.

  python3 plot_paper.py cliff   -> fig_cliff.png       (Fig 6a: iteration vs EP, per system)
  python3 plot_paper.py decomp  -> fig_decomp.png      (Fig 6b: EP=32 gap decomposition)
  python3 plot_paper.py beyond  -> fig_beyond.png      (Fig 6c: EP=128 training, every fabric past the NVL boundary)
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
try:
    sys.path.insert(0, os.path.dirname(__file__)); import paper_style as _ps; _ps.apply()
except Exception:
    _ps = None

RES = os.environ.get("PAPER_RES", os.path.join(os.path.dirname(__file__), "..", "..", "experiments", "results", "paper"))
OUT = os.environ.get("OUT", ".")
SYS_LABEL = {"glassfb": "Glass-FB", "hgx8": "HGX-8", "nvl64": "NVL-64", "flat900_capped": "900 GB/s no-boundary bound",
             "flat900_uncapped": "900 GB/s uncapped", "copperfb": "Copper-FB @100",
             "glass_A": "A: as submitted", "glass_B": "B: +placement", "glass_C": "C: +16-port cabling",
             "glassfb_mesh": "Glass-FB (4-edge mesh)", "glassfb_hier": "Glass-FB (hier. A2A)", "nvl64_pkt": "NVL-64 (packet-level)", "hgx8_pkt": "HGX-8 (packet-level)",
             "nvl64_pkt_s1": "NVL-64 (packet-level, striped: 1x900)"}
SYS_COLOR = {"glassfb": "#1f6f8b", "glassfb_mesh": "#7fb3c8", "glassfb_hier": "#0b3d4f", "hgx8": "#d95f0e", "hgx8_pkt": "#d95f0e", "nvl64": "#7a0177", "nvl64_pkt": "#7a0177", "nvl64_pkt_s1": "#b06fc0", "flat900_capped": "#7a0177",
             "flat900_uncapped": "#b8a0c8", "copperfb": "#8c6d31"}

def load(ref):
    p = os.path.join(RES, f"{ref}.csv")
    if not os.path.exists(p):
        sys.exit(f"missing {p} (paper_ref={ref} rows have not landed)")
    rows = [r for r in csv.DictReader(open(p)) if r.get("status", "final") == "final"]
    # quotable=yes -> drawn solid; quotable=no/grid -> kept only as hollow sensitivity points
    for r in rows:
        qf = (r.get("quotable") or "").lower()
        r["_quotable"] = qf == "yes" or (qf == "" and str(r.get("rtos", "")) in ("0", "0.0"))
    if not rows:
        sys.exit(f"{p}: no rows with status=final")
    for r in rows:
        for k in ("ep", "mb", "nodes", "rtos"):
            if r.get(k): r[k] = int(float(r[k]))
        for k in ("makespan_ms", "compute_cp_ms", "mean_fct_ms", "p99_fct_ms", "max_fct_ms"):
            if r.get(k): r[k] = float(r[k])
    print(f"[{ref}] {len(rows)} final rows:", ", ".join(sorted({f"{r.get('system') or r.get('label')}@EP{r.get('ep')}" for r in rows})))
    return rows

def mname(r):
    """Workload name. cliff.csv used to call this `model`; that column now
    carries the family (island|pkt|glass), matching cliff_pkt.csv. The
    fallback keeps un-migrated CSVs plotting correctly."""
    return r.get("model_name") or r.get("model")

def f(name):
    return os.path.join(OUT, name)

def cliff():
    rows = load("cliff_all")   # single source built by build_cliff_table.py (carries quotable + source)
    rows = [r for r in rows if str(r.get("mb") or 8) == "8"]   # mb is int after load()
    # one drawn point per (system, ep): the quotable row with the lowest makespan; otherwise the
    # lowest non-quotable (drawn hollow). Repeated sensitivity rows (same makespan at several q)
    # collapse to one.
    best = {}
    for r in rows:
        k = (r["system"], r["ep"])
        cur = best.get(k)
        if cur is None or (r["_quotable"] and not cur["_quotable"]) or (r["_quotable"] == cur["_quotable"] and r["makespan_ms"] < cur["makespan_ms"]):
            best[k] = r
    rows = list(best.values())
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    for sysname in ("hgx8", "hgx8_pkt", "nvl64", "nvl64_pkt", "nvl64_pkt_s1", "glassfb_mesh", "glassfb", "glassfb_hier"):
        pts = sorted([(r["ep"], r["makespan_ms"], r) for r in rows if r["system"] == sysname and r["_quotable"]])
        sens = sorted([(r["ep"], r["makespan_ms"], r) for r in rows if r["system"] == sysname and not r["_quotable"]])
        if not pts and not sens: continue
        dashed = sysname in ("hgx8", "nvl64")  # analytic island = vendor-claim upper bound
        if pts:
            ax.plot([p[0] for p in pts], [p[1] for p in pts], "--" if dashed else ("s-." if sysname == "nvl64_pkt_s1" else "o-"), color=SYS_COLOR[sysname],
                    label=SYS_LABEL[sysname] + (" (vendor-claim bound)" if dashed else ""), lw=1.2 if dashed else 1.5, ms=4, alpha=0.8 if dashed else 1)
        if sens:  # not at its zero-timeout buffer (or a grid cell): hollow, unconnected
            ax.plot([p[0] for p in sens], [p[1] for p in sens], linestyle="none", marker="o", markerfacecolor="white",
                    color=SYS_COLOR[sysname], ms=4, alpha=0.9)
        for ep, y, r in pts:
            if r.get("rtos") and r["rtos"] > 0:
                ax.annotate(f"{r['rtos']:,} RTO", (ep, y), fontsize=5, textcoords="offset points", xytext=(3, 3))
    # model per point
    models = {}
    for r in sorted(rows, key=lambda r: 0 if r["system"] == "glassfb" else 1):   # label each EP by the glass row's model
        models.setdefault(r["ep"], (r.get("model_name") or "") + (f" top-{r['topk']}" if r.get("topk") else ""))
    ax.set_xscale("log", base=2); ax.set_xticks(sorted(models)); ax.set_xticklabels([f"{ep}\n{models[ep]}" for ep in sorted(models)], fontsize=5.5)
    ax.set_yscale("log"); ax.set_ylabel("iteration (ms)", fontsize=7); ax.set_xlabel("EP degree (model per point)", fontsize=7)
    ax.axvline(16, color="#1f6f8b", ls=":", lw=0.8); ax.axvline(8, color="#d95f0e", ls=":", lw=0.8); ax.axvline(64, color="#7a0177", ls=":", lw=0.8)
    ax.tick_params(labelsize=6); ax.legend(fontsize=5.5, frameon=False); ax.grid(alpha=0.3, which="both")
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_cliff.png")); print("wrote fig_cliff.png")

def decomp():
    """R2: critical-path decomposition per class (decomp_critpath.csv; label = '<system> EP=<n> q=<q>')."""
    import re
    rows = load("decomp_critpath")
    classes = [("compute_ms", "compute", "compute"), ("expert_a2a_ms", "expert A2A", "a2a_inter"),
               ("dp_allreduce_ms", "DP all-reduce", "dp"), ("pp_p2p_ms", "PP p2p", "pp"), ("other_ms", "other", "tail")]
    # only rows whose (system, ep, q) is a quotable cliff row (sweep rows with timeouts stay out)
    # keyed on (system, ep, makespan) because the labels spell the buffer three ways
    # ("q=2133", "q2176", "k64"); the makespan is the row's identity in both tables
    quot = set()
    try:
        for c in csv.DictReader(open(os.path.join(RES, "cliff_all.csv"))):
            if (c.get("quotable") or "").lower() == "yes":
                quot.add((c["system"], str(int(float(c["ep"]))), round(float(c["makespan_ms"]), 3)))
    except Exception:
        quot = None
    parsed = []
    for r in rows:
        m = re.match(r"(\S+) EP=(\d+)", r["label"])
        if not m: continue
        key = (m.group(1), m.group(2), round(float(r["makespan_ms"]), 3))
        if quot is not None and key not in quot:
            print(f"[decomp] skip {r['label']}: not a quotable cliff row"); continue
        parsed.append((int(m.group(2)), m.group(1), r))
    parsed.sort(key=lambda t: (t[0], 0 if t[1] == "glassfb" else 1))
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    xs, labels = [], []; x = 0
    for ep, sysname, r in parsed:
        bottom = 0.0
        for col, lab, ckey in classes:
            v = float(r.get(col) or 0)
            if v <= 0: continue
            ax.bar(x, v, bottom=bottom, width=0.7, color=_ps.COL.get(ckey, "#999") if _ps else None,
                   edgecolor=SYS_COLOR.get(sysname, "#333"), linewidth=0.8, label=lab if x == 0 else None)
            bottom += v
        ax.text(x, bottom * 1.02, f"{bottom:.1f}", ha="center", fontsize=5.5)
        xs.append(x); labels.append(f"{SYS_LABEL.get(sysname, sysname).split(' (')[0]}\nEP={ep}"); x += 1
        if sysname != "glassfb": x += 0.5
    ax.set_xticks(xs); ax.set_xticklabels(labels, fontsize=5.5)
    ax.set_ylabel("critical-path time (ms)", fontsize=7); ax.tick_params(labelsize=6)
    ax.legend(fontsize=5.5, frameon=False, loc="upper left")
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_decomp.png")); print("wrote fig_decomp.png")

def beyond():
    """R-beyond (Fig 6c): every fabric past the NVL boundary, EP=128 (Arctic top-2) from cliff_all.
    One bar per system: the quotable row (solid) or, until it exists, the best non-quotable row
    (hollow, timeout count labelled) -- the same rule as R1. Bound rows (island) drawn as a dashed
    line, not a bar."""
    rows = [r for r in load("cliff_all") if r["ep"] == 128 and str(r.get("mb") or 8) == "8"]
    if not rows: sys.exit("beyond: no EP=128 rows in cliff_all")
    best = {}
    for r in rows:
        cur = best.get(r["system"])
        if cur is None or (r["_quotable"] and not cur["_quotable"]) or (r["_quotable"] == cur["_quotable"] and r["makespan_ms"] < cur["makespan_ms"]):
            best[r["system"]] = r
    order = [s_ for s_ in ("glassfb", "nvl64_pkt", "nvl64_pkt_s1", "hgx8_pkt") if s_ in best]
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    g = best.get("glassfb")
    for x, s_ in enumerate(order):
        r = best[s_]; y = r["makespan_ms"]
        if r["_quotable"]:
            ax.bar(x, y, color=SYS_COLOR[s_], width=0.7)
        else:
            ax.bar(x, y, facecolor="white", edgecolor=SYS_COLOR[s_], lw=1.4, width=0.7)
        lab = f"{y:.0f}" + ("" if r["_quotable"] else f"\n{r['rtos']:,} RTO")
        ax.text(x, y * 1.02, lab, ha="center", va="bottom", fontsize=5.5)
        if g is not None and s_ != "glassfb" and g["_quotable"] and r["_quotable"]:
            ax.text(x, y * 0.5, f"{y / g['makespan_ms']:.2f}x", ha="center", color="white", fontsize=6, fontweight="bold")
    for s_ in ("nvl64", "hgx8"):   # vendor-claim bounds
        if s_ in best:
            ax.axhline(best[s_]["makespan_ms"], color=SYS_COLOR[s_], ls="--", lw=1.0, alpha=0.8, label=SYS_LABEL[s_] + " bound")
    ax.set_xticks(range(len(order))); ax.set_xticklabels([SYS_LABEL[s_].replace(" (packet-level)", "\n(packet-level)") for s_ in order], fontsize=6)
    ax.set_ylabel("iteration (ms)", fontsize=7); ax.tick_params(labelsize=6)
    m = next((r for r in rows if r["system"] == "glassfb"), rows[0])
    ax.set_title(f"EP=128, {mname(m)}" + (f" top-{m['topk']}" if m.get("topk") else "") + ", 1024 GPUs, 64 panels", fontsize=6.5)
    ax.set_ylim(0, max(best[s_]["makespan_ms"] for s_ in order) * 1.25)
    if any(s_ in best for s_ in ("nvl64", "hgx8")): ax.legend(fontsize=5.5, frameon=False)
    ax.grid(alpha=0.3, axis="y")
    print("[beyond] drawn:", ", ".join(f"{s_}={best[s_]['makespan_ms']} ({'quotable' if best[s_]['_quotable'] else 'hollow'})" for s_ in order))
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_beyond.png")); print("wrote fig_beyond.png")

def mb():
    """R6: iteration vs microbatch at EP=16, glass vs the queued NVL-64 domain (quotable rows of cliff_all)."""
    rows = [r for r in load("cliff_all") if r["_quotable"] and str(r.get("ep")) == "16" and r.get("mb")]
    fig, ax = plt.subplots(figsize=(3.4, 2.4), dpi=200)
    for sysname in ("nvl64_pkt", "glassfb"):
        best = {}
        for r in rows:
            if r["system"] != sysname: continue
            m = int(r["mb"]); best[m] = min(best.get(m, 1e9), r["makespan_ms"])
        pts = sorted(best.items())
        if not pts: continue
        st = _ps.style_line(sysname) if _ps else dict(color=SYS_COLOR[sysname], marker="o", label=SYS_LABEL[sysname])
        ax.plot([p[0] for p in pts], [p[1] for p in pts], "-", **st)
        for m, v in pts: ax.text(m, v * 1.03, f"{v:.0f}", ha="center", fontsize=5.5, color=st["color"])
    ax.set_xscale("log", base=2); ax.set_xticks([4, 8, 16, 32]); ax.set_xticklabels([4, 8, 16, 32])
    ax.set_xlabel("microbatch (LLaMA-MoE, EP=16)", fontsize=7); ax.set_ylabel("iteration (ms)", fontsize=7); ax.tick_params(labelsize=6)
    ax.legend(fontsize=5.5, frameon=False, loc="upper left"); ax.grid(alpha=0.3)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_mb.png")); print("wrote fig_mb.png")

def ladder():
    """R3: the cabling x dim-order 2x2 at EP=32 (dse_cabling_2x2.csv), plus the quoted port-map row
    at its zero-timeout buffer, with the queued NVL-64 and the bound as reference lines."""
    rows = load("dse_cabling_2x2")
    cells = {(r["cabling"], str(r["dim_a2a"])): r for r in rows}
    fig, ax = plt.subplots(figsize=(3.4, 2.6), dpi=200)
    order = [("mesh", "0", "mesh\nrelay off"), ("mesh", "1", "mesh\nrelay on"), ("portmap", "0", "port map\nrelay off"), ("portmap", "1", "port map\nrelay on")]
    xs, labs = [], []
    for x, (cab, dim, lab) in enumerate(order):
        r = cells.get((cab, dim))
        if not r: continue
        col = SYS_COLOR["glassfb_mesh"] if cab == "mesh" else SYS_COLOR["glassfb"]
        ax.bar(x, r["makespan_ms"], color=col, width=0.7)
        ax.text(x, r["makespan_ms"] * 1.02, f"{r['makespan_ms']:.0f}\n{int(float(r['rtos'])):,} RTO", ha="center", fontsize=5.2, linespacing=0.9)
        xs.append(x); labs.append(lab)
    # quoted row (port map, relay on, zero-timeout buffer) from cliff_all
    try:
        q = [c for c in csv.DictReader(open(os.path.join(RES, "cliff_all.csv")))
             if c["system"] == "glassfb" and c["ep"] == "32" and (c.get("quotable") or "").lower() == "yes"]
        if q:
            v = min(float(c["makespan_ms"]) for c in q)
            ax.bar(len(order), v, color=SYS_COLOR["glassfb"], width=0.7, hatch="..")
            ax.text(len(order), v * 1.02, f"{v:.0f}\n0 RTO", ha="center", fontsize=5.2, linespacing=0.9)
            xs.append(len(order)); labs.append("port map\nquoted q")
        n = [c for c in csv.DictReader(open(os.path.join(RES, "cliff_all.csv")))
             if c["system"] == "nvl64_pkt" and c["ep"] == "32" and (c.get("quotable") or "").lower() == "yes"]
        if n:
            v = min(float(c["makespan_ms"]) for c in n)
            ax.axhline(v, color=SYS_COLOR["nvl64_pkt"], lw=0.9); ax.text(len(order) + 0.45, v * 1.02, f"NVL-64 queued {v:.0f}", color=SYS_COLOR["nvl64_pkt"], fontsize=5.5, ha="right")
        b = [c for c in csv.DictReader(open(os.path.join(RES, "cliff_all.csv"))) if c["system"] == "nvl64" and c["ep"] == "32"]
        if b:
            v = min(float(c["makespan_ms"]) for c in b)
            ax.axhline(v, color=SYS_COLOR["nvl64"], lw=0.9, ls="--"); ax.text(len(order) + 0.45, v * 1.02, f"bound {v:.0f}", color=SYS_COLOR["nvl64"], fontsize=5.5, ha="right")
    except Exception as e:
        print("[ladder] reference lines skipped:", e)
    ax.set_xticks(xs); ax.set_xticklabels(labs, fontsize=5.5)
    ax.set_ylabel("EP=32 iteration (ms)", fontsize=7); ax.tick_params(labelsize=6)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_ladder.png")); print("wrote fig_ladder.png")

def energy():
    """R5: per-iteration interconnect energy, link (bytes moved) vs static, both pJ/bit ends, per EP."""
    g = load("power_tiers"); n = load("power_tiers_pkt")
    eps = sorted({int(r["ep"]) for r in g} | {int(r["ep"]) for r in n})
    systems = ["glassfb", "nvl64_pkt", "hgx8_pkt"]
    fig, axes = plt.subplots(1, len(eps), figsize=(3.4, 2.4), dpi=200, sharey=True)
    axes = list(axes) if len(eps) > 1 else [axes]
    for ax, ep in zip(axes, eps):
        for x, sysname in enumerate(systems):
            r = next((r for r in (g + n) if r["system"] == sysname and int(r["ep"]) == ep), None)
            if not r: continue
            lo, hi = float(r["link_J_iter_lo"]), float(r["link_J_iter_hi"])
            slo = float(r.get("static_J_iter_lo") or r.get("static_J_iter") or 0); shi = float(r.get("static_J_iter_hi") or r.get("static_J_iter") or slo)
            c = SYS_COLOR.get(sysname, "#999")
            ax.bar(x, hi, color=c, alpha=0.35, width=0.6); ax.bar(x, lo, color=c, width=0.6)               # link: dark = favourable end
            ax.bar(x, shi, bottom=hi, color="none", edgecolor=c, hatch="////", width=0.6, lw=0.6)          # static (assumed), hatched
            ax.bar(x, slo, bottom=hi, color="none", edgecolor=c, width=0.6, lw=0.6)
            ax.text(x, hi + shi + 3, f"{lo:.0f}–{hi:.0f}\n+{slo:.0f}–{shi:.0f}", ha="center", fontsize=4.8, linespacing=0.9)
        ax.set_xticks(range(len(systems))); ax.set_xticklabels([SYS_LABEL[s].split(" (")[0] for s in systems], fontsize=5.5, rotation=20)
        ax.set_title(f"EP={ep}", fontsize=7); ax.tick_params(labelsize=6)
    axes[0].set_ylabel("J per iteration (solid: link, bytes moved;\nhatched: static, assumed)", fontsize=6)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_energy.png")); print("wrote fig_energy.png")

def tail():
    """R4: buffer vs tail. For each (system, ep) sweep in buffer_sweeps.csv: makespan (bars) and payload
    max FCT (line, right axis) against q_over_bdp; RTO count as labels; quotable point filled."""
    rows = load("buffer_sweeps")
    groups = {}
    for r in rows:
        try:
            q = float(r["q_over_bdp"]); mk = float(r["makespan_ms"])
        except (TypeError, ValueError):
            continue
        mx = r.get("max_fct_ms")
        try:
            mx = float(mx) if mx not in (None, "") else None
            if (r.get("fct_status") or "clean") != "clean": mx = None   # tail drawn only from an uncollided FCT log
            if mx is not None and mx > mk: mx = None      # a collided / non-time value
        except ValueError:
            mx = None
        groups.setdefault((r["system"], int(r["ep"])), []).append((q, mk, int(float(r.get("rtos") or 0)), mx, (r.get("quotable") or "").lower() == "yes"))
    # collapse each sweep to power-of-two buffer steps (the fine sweeps sit within one step):
    # per step keep the quotable point if any, else the lowest makespan
    import math
    for k, pts in groups.items():
        step = {}
        for q, mk, rto, mx, quo in pts:
            b = int(round(math.log2(q)))
            cur = step.get(b)
            if cur is None or (quo and not cur[4]) or (quo == cur[4] and mk < cur[1]):
                step[b] = (2 ** b, mk, rto, mx, quo)
        groups[k] = list(step.values())
    want = [("nvl64_pkt", 16), ("glassfb", 32), ("nvl64_pkt", 32), ("glassfb", 64), ("nvl64_pkt", 64)]
    panels = [(k, sorted(groups[k])) for k in want if k in groups and len(groups[k]) >= 2]
    if not panels: sys.exit("buffer_sweeps: no multi-point sweeps")
    fig, axes = plt.subplots(1, len(panels), figsize=(DBL_W_ if False else 7.16, 2.2), dpi=200)
    axes = list(axes) if len(panels) > 1 else [axes]
    for ax, ((sysname, ep), pts) in zip(axes, panels):
        xs = list(range(len(pts))); c = SYS_COLOR.get(sysname, "#333")
        ax.bar(xs, [p[1] for p in pts], color=[c if p[4] else "white" for p in pts], edgecolor=c, width=0.65)
        for x, (q, mk, rto, mx, quo) in zip(xs, pts):
            ax.text(x, mk * 1.02, f"{rto:,}" if rto else "0", ha="center", fontsize=4.8)
        ax.set_xticks(xs); ax.set_xticklabels([f"{p[0]:g}×" for p in pts], fontsize=5.5)
        ax.set_title(f"{SYS_LABEL.get(sysname, sysname).split(' (')[0]}, EP={ep}", fontsize=6.5)
        ax.tick_params(labelsize=5.5); ax.set_ylim(0, max(p[1] for p in pts) * 1.25)
        ax2 = ax.twinx()
        mxs = [(x, p[3]) for x, p in zip(xs, pts) if p[3] is not None]
        if mxs:
            ax2.plot([m[0] for m in mxs], [m[1] for m in mxs], color="#b22222", marker="D", ms=3, lw=1)
        ax2.tick_params(axis="y", colors="#b22222", labelsize=5.5); ax2.grid(False); ax2.spines["right"].set_visible(True)
        if ax is axes[-1]: ax2.set_ylabel("max FCT (ms)", color="#b22222", fontsize=6)
    axes[0].set_ylabel("iteration (ms); label = timeouts", fontsize=6)
    fig.text(0.5, 0.005, "queue depth (× port round-trip BDP); filled = quoted row", ha="center", fontsize=6)
    fig.tight_layout(pad=0.3, rect=(0, 0.03, 1, 1)); fig.savefig(f("fig_tail.png")); print("wrote fig_tail.png")

if __name__ == "__main__":
    which = sys.argv[1:] or ["all"]
    fns = {"cliff": cliff, "decomp": decomp, "beyond": beyond, "mb": mb, "ladder": ladder, "energy": energy, "tail": tail}
    for w in (fns if "all" in which else which):
        try: fns[w]()
        except SystemExit as e: print("skip:", e)
