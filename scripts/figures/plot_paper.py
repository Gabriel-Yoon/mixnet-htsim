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
import csv
import re, os, re, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
try:
    sys.path.insert(0, os.path.dirname(__file__)); import paper_style as _ps; _ps.apply()
except Exception:
    _ps = None

RES = os.environ.get("PAPER_RES", os.path.join(os.path.dirname(__file__), "..", "..", "experiments", "results", "paper"))
OUT = os.environ.get("OUT", ".")
SYS_LABEL = {"glassfb": "Glass-FB", "hgx8": "HGX-8", "nvl64": "NVL72", "flat900_capped": "900 GB/s no-boundary bound",
             "flat900_uncapped": "900 GB/s uncapped", "copperfb": "Copper-FB @100",
             "glass_A": "A: as submitted", "glass_B": "B: +placement", "glass_C": "C: +16-port cabling",
             "glassfb_mesh": "Glass-FB (4-edge mesh)", "glassfb_hier": "Glass-FB (hier. A2A)", "nvl64_pkt": "NVL72 (packet-level)", "hgx8_pkt": "HGX-8 (packet-level)",
             "nvl64_pkt_s1": "NVL72 (packet-level, striped: 1x900)", "glassfb_800": "Glass-FB, 200G/lane ports (800 GB/s)"}
SYS_COLOR = {"glassfb": "#1f6f8b", "glassfb_mesh": "#7fb3c8", "glassfb_hier": "#0b3d4f", "hgx8": "#d95f0e", "hgx8_pkt": "#d95f0e", "nvl64": "#7a0177", "nvl64_pkt": "#7a0177", "nvl64_pkt_s1": "#b06fc0", "glassfb_800": "#2a9d8f", "flat900_capped": "#7a0177",
             "flat900_uncapped": "#b8a0c8", "copperfb": "#8c6d31"}

def load(ref):
    p = os.path.join(RES, f"{ref}.csv")
    if not os.path.exists(p):
        sys.exit(f"missing {p} (paper_ref={ref} rows have not landed)")
    rows = [r for r in csv.DictReader(open(p)) if r.get("status", "final") == "final"]
    # quotable=yes -> drawn solid; anything else -> kept only as hollow sensitivity points.
    #
    # An unstamped row is NOT quotable. The old fallback promoted any row with zero
    # timeouts, which is the per-row rule the gate is specifically forbidden to apply
    # to a ladder -- every clean rung of a walk passes it, not just the first. A file
    # that reaches the figures before gate_quotable.py has stamped it would have been
    # drawn under that rule with nothing to show it had happened.
    unstamped = 0
    for r in rows:
        qf = (r.get("quotable") or "").lower()
        if qf == "" and str(r.get("rtos", "")) not in ("",):
            unstamped += 1
        r["_quotable"] = qf == "yes"
    if unstamped:
        print("  WARNING %s: %d row(s) carry timeouts but no quotable stamp -- drawn hollow; "
              "run scripts/gate_quotable.py" % (os.path.basename(p), unstamped))
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

# NOT a microbatch rule: cliff() already keeps mb 8 only, and "m\d+$" additionally
# threw out g16m8 -- the mb=8 cell IS glass's plain EP=16 walk, there is no separate
# g16 -- leaving EP=16 drawn hollow from a pre-fix portmap row at 86.750 instead of
# the post-fix 87.613. Skew, hierarchical A2A and the 2x2 cabling grid only.
# Skew, hierarchical A2A, the 2x2 cabling grid, and the placement-off ablation. NOT a microbatch rule: cliff()
# already keeps mb 8 only, and adding "m\d+$" here additionally threw out g16m8 --
# the mb=8 cell IS glass's plain EP=16 walk, there is no separate g16 -- which left
# EP=16 drawn hollow from a pre-fix portmap row at 86.750 instead of the post-fix
# 87.613. A filter that removes the row it was meant to keep is worse than none.
def _rung_key(r):
    """Sort key among equally-quotable rows: ladder position, then makespan.

    A row with no q (the analytic island bounds) sorts last, so a measured rung
    always wins over a bound when both are quotable at one (system, ep).
    """
    try:
        q = float(r.get("q"))
    except (TypeError, ValueError):
        q = float("inf")
    return (q, r["makespan_ms"])

_VARIANT_CELL = re.compile(r"hier|sk\d|^x2_|^npl|^mix")


def headline_only(rows, what):
    """Drop configuration cells that share (system, ep) with the plain walk.

    g32 / sk1p2 / sk2p0 / hier32 are four different experiments at one (system, ep,
    mb); each is the first clean rung of its OWN walk, so each is legitimately
    quotable, and a figure that picks the lowest makespan among them draws the
    kindest configuration and labels it the plain one. R1 drew sk1p2's 74.814 ms as
    glass EP=32 against incumbents measured unskewed; the plain walk is 77.918.

    A row with no variant (the analytic island tables and the older sweeps) is a
    headline row: there is nothing it could be a variant of.
    """
    keep, dropped = [], {}
    for r in rows:
        v = (r.get("walk") or "").strip()
        if v and _VARIANT_CELL.search(v):
            dropped.setdefault(v, 0)
            dropped[v] += 1
        else:
            keep.append(r)
    if dropped:
        print("  [%s] variant cells excluded: %s" % (
            what, ", ".join("%s x%d" % (k, n) for k, n in sorted(dropped.items()))))
    if not keep:
        print("  [%s] WARNING every row is a variant cell; keeping them all" % what)
        return rows
    return keep

def cliff():
    rows = load("cliff_all")   # single source built by build_cliff_table.py (carries quotable + source)
    rows = [r for r in rows if str(r.get("mb") or 8) == "8"]   # mb is int after load()
    rows = headline_only(rows, "cliff")
    # one drawn point per (system, ep): the quotable row with the lowest makespan; otherwise the
    # lowest non-quotable (drawn hollow). Repeated sensitivity rows (same makespan at several q)
    # collapse to one.
    best = {}
    for r in rows:
        k = (r["system"], r["ep"])
        cur = best.get(k)
        if cur is None or (r["_quotable"] and not cur["_quotable"]) or (
                r["_quotable"] == cur["_quotable"] and
                (_rung_key(r) < _rung_key(cur) if r["_quotable"]
                 else r["makespan_ms"] < cur["makespan_ms"])):
            best[k] = r
    # The tiebreak below takes the lowest makespan, which is correct only because the
    # walk-level pass marks ONE rung quotable per key. If it ever marks more, this
    # silently draws the fastest clean rung instead of the first -- say so.
    for k in best:
        n = sum(1 for r in rows if (r["system"], r["ep"]) == k and r["_quotable"])
        if n > 1:
            print("  WARNING cliff %s ep=%s: %d quotable rows, the walk rule allows one; "
                  "drew the first rung (q=%s)" % (k[0], k[1], n, best[k].get("q")))
    rows = list(best.values())
    SHORTLAB = {"hgx8": "HGX-8 bound", "hgx8_pkt": "HGX-8", "nvl64": "NVL72 bound", "nvl64_pkt": "NVL72 pinned",
                "nvl64_pkt_s1": "NVL72 striped", "glassfb": "Glass-FB", "glassfb_800": "Glass-FB, 200G/lane ports"}
    fig, ax = plt.subplots(figsize=(3.4, 2.7), dpi=200)
    # HGX-8's island and packet-level rows coincide, so its bound line is not drawn
    for sysname in ("hgx8_pkt", "nvl64", "nvl64_pkt", "nvl64_pkt_s1", "glassfb", "glassfb_800"):
        pts = sorted([(r["ep"], r["makespan_ms"], r) for r in rows if r["system"] == sysname and r["_quotable"]])
        sens = sorted([(r["ep"], r["makespan_ms"], r) for r in rows if r["system"] == sysname and not r["_quotable"]])
        if not pts and not sens: continue
        dashed = sysname in ("hgx8", "nvl64")  # analytic island = vendor-claim upper bound
        if pts:
            ax.plot([p[0] for p in pts], [p[1] for p in pts], "--" if dashed else ("s-." if sysname == "nvl64_pkt_s1" else ("D:" if sysname == "glassfb_800" else "o-")), color=SYS_COLOR[sysname],
                    label=SHORTLAB.get(sysname, SYS_LABEL[sysname]), lw=1.2 if dashed else 1.5, ms=4, alpha=0.8 if dashed else 1)
            if sysname == "nvl64_pkt_s1":   # calibrated estimate of the machine: striped x 1.25-1.4 (large-message optimism)
                xs_ = [p[0] for p in pts]; ys_ = [p[1] for p in pts]
                ax.fill_between(xs_, [y * 1.25 for y in ys_], [y * 1.40 for y in ys_], color=SYS_COLOR[sysname], alpha=0.18, lw=0,
                                label="NVL72 calibrated estimate (striped x 1.25-1.4)")
        if sens:  # not at its zero-timeout buffer (or a grid cell): hollow, unconnected
            ax.plot([p[0] for p in sens], [p[1] for p in sens], linestyle="none", marker="o", markerfacecolor="white",
                    color=SYS_COLOR[sysname], ms=4, alpha=0.9)
        for ep, y, r in sens:   # hollow packet-level points carry their timeout count; quoted rows passed the measured-loss gate
            if r.get("rtos") and r["rtos"] > 0 and not dashed:
                ax.annotate(f"{r['rtos']:,} RTO", (ep, y), fontsize=4.6, textcoords="offset points", xytext=(3, 3))
    # compute floor per EP (grey tick): the glass row's compute contribution from decomp_critpath, so the
    # reader sees that the model, not the fabric, sets the level at each EP
    try:
        floor = {}
        for d in csv.DictReader(open(os.path.join(RES, "decomp_critpath.csv"))):
            mm = re.match(r"glassfb EP=(\d+)", d["label"])
            if mm and not re.search(r"hier|sk\d|mix|npl|mb=(4|16|32)\b", d["label"]):
                floor.setdefault(int(mm.group(1)), float(d["compute_ms"]))
        for ep_, c_ in floor.items():
            ax.plot([ep_ / 1.10, ep_ * 1.10], [c_, c_], color="#8a949b", lw=1.1, zorder=1)
        if floor:
            ax.plot([], [], color="#8a949b", lw=1.1, label="compute floor of the model at that EP")
    except Exception as e:
        print("[cliff] no compute floor:", e)
    # model per point
    models = {}
    # label each EP by the glass row's model; a row with a blank model_name (collector rows) defers to
    # any other row at that EP that carries one
    for r in sorted(rows, key=lambda r: (0 if r.get("model_name") else 1, 0 if r["system"] == "glassfb" else 1)):
        if not r.get("model_name"): models.setdefault(r["ep"], ""); continue
        if not models.get(r["ep"]):
            models[r["ep"]] = (r.get("model_name") or "") + (f" top-{r['topk']}" if r.get("topk") else "")
    ax.set_xscale("log", base=2); ax.set_xticks(sorted(models)); ax.set_xticklabels([f"{ep}\n{models[ep]}" for ep in sorted(models)], fontsize=5.5)
    ax.set_yscale("log"); ax.set_ylabel("iteration (ms)", fontsize=7); ax.set_xlabel("EP degree (model per point)", fontsize=7)
    ax.axvline(16, color="#1f6f8b", ls=":", lw=0.8); ax.axvline(64, color="#7a0177", ls=":", lw=0.8)
    ax.text(16, ax.get_ylim()[0], " panel", color="#1f6f8b", fontsize=5, va="bottom", ha="left")
    ax.text(64, ax.get_ylim()[0], " NVL72", color="#7a0177", fontsize=5, va="bottom", ha="left")
    ax.tick_params(labelsize=6); ax.grid(alpha=0.25, which="both")
    ax.set_ylim(ax.get_ylim()[0], ax.get_ylim()[1] * 2.2)   # headroom for the legend
    ax.legend(fontsize=4.6, frameon=False, ncol=2, loc="upper left", handlelength=2.0, columnspacing=0.8, borderaxespad=0.3)
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
    # headline rows only: the quotable cliff row of each (system, ep) at the default microbatch
    # (mb 8 or unset); variant cells (mb sweep, skew, hier) share system/ep and are excluded by
    # label, and duplicate decomp rows of one quoted makespan collapse to the first
    HEAD = ("glassfb_800", "glassfb", "nvl64_pkt_s1", "hgx8_pkt")   # NVL72 = the striped model (calibrated end); pinned rows not drawn
    PRIMARY_GLASS = os.environ.get("PRIMARY_GLASS", "glassfb_800")   # design point: 200G/lane ports
    quot = set()
    try:
        for c in csv.DictReader(open(os.path.join(RES, "cliff_all.csv"))):
            if (c.get("quotable") or "").lower() == "yes" and c["system"] in HEAD and str(c.get("mb") or "8") == "8":
                quot.add((c["system"], str(int(float(c["ep"]))), round(float(c["makespan_ms"]), 3)))
    except Exception:
        quot = None
    parsed = []; seen = set()
    for r in rows:
        m = re.match(r"(\S+) EP=(\d+)", r["label"])
        if not m: continue
        if re.search(r"hier|sk\d|mix|npl|mb=(4|16|32)\b", r["label"]): continue
        if int(m.group(2)) < 16: continue   # placement-ablation configurations are not headline groups
        key = (m.group(1), m.group(2), round(float(r["makespan_ms"]), 3))
        r["_hollow"] = "BEST-RUNG-NOT-QUOTED" in r["label"]   # a walk with no zero-timeout rung: drawn hollow
        if quot is not None and key not in quot and not r["_hollow"]:
            print(f"[decomp] skip {r['label']}: not a quotable cliff row"); continue
        if key in seen: continue
        seen.add(key); parsed.append((int(m.group(2)), m.group(1), r))
    # where the design-point glass row exists at an EP, the other glass variant is dropped from the group
    eps_with_primary = {ep for ep, sysn, _ in parsed if sysn == PRIMARY_GLASS}
    parsed = [t for t in parsed if not (t[1] in ("glassfb", "glassfb_800") and t[1] != PRIMARY_GLASS and t[0] in eps_with_primary)]
    parsed.sort(key=lambda t: (t[0], HEAD.index(t[1]) if t[1] in HEAD else 9))
    fig, ax = plt.subplots(figsize=(7.0, 2.7), dpi=200)
    SHORT = {"glassfb": "Glass-FB (100G/lane)", "glassfb_800": "Glass-FB", "nvl64_pkt_s1": "NVL72", "hgx8_pkt": "HGX-8"}
    DARK = {"glassfb_800": "#2b6f7f", "glassfb": "#2b6f7f", "nvl64_pkt_s1": "#4b3f8f", "hgx8_pkt": "#c46a4a"}
    LIGHT = {"glassfb_800": "#c9dfe4", "glassfb": "#c9dfe4", "nvl64_pkt_s1": "#cfc9e8", "hgx8_pkt": "#efd3c6"}
    xs, labels = [], []; x = 0; groups = {}
    for ep, sysname, r in parsed:
        comp = float(r.get("compute_ms") or 0); a2a = float(r.get("expert_a2a_ms") or 0)
        other = sum(float(r.get(c) or 0) for c in ("dp_allreduce_ms", "pp_p2p_ms", "other_ms"))
        hol = r.get("_hollow")
        ax.bar(x, comp, width=0.72, color=LIGHT[sysname], edgecolor=DARK[sysname], linewidth=0.7, alpha=0.5 if hol else 1.0, hatch="//" if hol else None)
        ax.bar(x, a2a + other, bottom=comp, width=0.72, color=DARK[sysname], edgecolor=DARK[sysname], linewidth=0.7, alpha=0.5 if hol else 1.0, hatch="//" if hol else None)
        tot = comp + a2a + other
        ax.text(x, tot * 1.015, f"{tot:.0f}" + ("*" if hol else ""), ha="center", va="bottom", fontsize=7)
        xs.append(x); labels.append(SHORT.get(sysname, sysname)); groups.setdefault(ep, []).append(x); x += 1
        if sysname == "hgx8_pkt": x += 0.9
    ax.set_xticks(xs); ax.set_xticklabels(labels, fontsize=8, rotation=30, ha="right")
    ymax = ax.get_ylim()[1] * 1.08
    for ep, gx in groups.items():   # EP group label above each group
        ax.text(sum(gx) / len(gx), ymax * 0.985, f"EP={ep}", ha="center", va="top", fontsize=9, fontweight="bold", color="#4a5560")
    ax.set_ylim(0, ymax)
    ax.set_ylabel("iteration time (ms)", fontsize=9); ax.tick_params(labelsize=8)
    import matplotlib.patches as mpatches_
    h = [mpatches_.Patch(facecolor="#5c6b74", label="expert all-to-all (dark)"), mpatches_.Patch(facecolor="#dfe4e7", edgecolor="#5c6b74", label="compute (light)")]
    ax.legend(handles=h, fontsize=8, frameon=False, loc="upper left", bbox_to_anchor=(0.0, 0.92))
    ax.grid(alpha=0.25, axis="y")
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_decomp.png")); print("wrote fig_decomp.png")

def beyond():
    """R-beyond (Fig 6c): every fabric past the NVL boundary, EP=128 (Arctic top-2) from cliff_all.
    One bar per system: the quotable row (solid) or, until it exists, the best non-quotable row
    (hollow, timeout count labelled) -- the same rule as R1. Bound rows (island) drawn as a dashed
    line, not a bar."""
    rows = [r for r in load("cliff_all") if r["ep"] == 128 and str(r.get("mb") or 8) == "8"]
    if not rows: sys.exit("beyond: no EP=128 rows in cliff_all")
    rows = headline_only(rows, "beyond")
    best = {}
    for r in rows:
        cur = best.get(r["system"])
        if cur is None or (r["_quotable"] and not cur["_quotable"]) or (
                r["_quotable"] == cur["_quotable"] and
                (_rung_key(r) < _rung_key(cur) if r["_quotable"]
                 else r["makespan_ms"] < cur["makespan_ms"])):
            best[r["system"]] = r
    for s_ in best:
        n = sum(1 for r in rows if r["system"] == s_ and r["_quotable"])
        if n > 1:
            print("  WARNING beyond %s: %d quotable rows, the walk rule allows one; "
                  "drew the first rung (q=%s)" % (s_, n, best[s_].get("q")))
    order = [s_ for s_ in ("glassfb", "glassfb_800", "nvl64_pkt", "nvl64_pkt_s1", "hgx8_pkt") if s_ in best]
    fig, ax = plt.subplots(figsize=(2.6, 2.7), dpi=200)
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
    BSHORT = {"glassfb": "Glass-FB", "glassfb_800": "Glass-FB\n200G/lane", "nvl64_pkt": "NVL72\npinned", "nvl64_pkt_s1": "NVL72\nstriped", "hgx8_pkt": "HGX-8"}
    ax.set_xticks(range(len(order))); ax.set_xticklabels([BSHORT.get(s_, s_) for s_ in order], fontsize=6)
    ax.set_ylabel("iteration (ms)", fontsize=7); ax.tick_params(labelsize=6)
    m = next((r for r in rows if r["system"] == "glassfb"), rows[0])
    ax.set_title(f"EP=128, {mname(m)}" + (f" top-{m['topk']}" if m.get("topk") else "") + ", 1024 GPUs, 64 panels", fontsize=6.5)
    ax.set_ylim(0, max(best[s_]["makespan_ms"] for s_ in order) * 1.25)
    if any(s_ in best for s_ in ("nvl64", "hgx8")): ax.legend(fontsize=5.5, frameon=False)
    ax.grid(alpha=0.3, axis="y")
    print("[beyond] drawn:", ", ".join(f"{s_}={best[s_]['makespan_ms']} ({'quotable' if best[s_]['_quotable'] else 'hollow'})" for s_ in order))
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_beyond.png")); print("wrote fig_beyond.png")

def mb():
    """R6: iteration vs microbatch at EP=16, glass vs the queued NVL72 domain (quotable rows of cliff_all)."""
    rows = [r for r in load("cliff_all") if r["_quotable"] and str(r.get("ep")) == "16" and r.get("mb")]
    fig, ax = plt.subplots(figsize=(3.4, 2.8), dpi=200)
    for sysname in ("nvl64_pkt", "nvl64_pkt_s1", "glassfb"):
        best = {}
        for r in rows:
            if r["system"] != sysname: continue
            m = int(r["mb"]); best[m] = min(best.get(m, 1e9), r["makespan_ms"])
        pts = sorted(best.items())
        if not pts: continue
        if sysname == "nvl64_pkt_s1":   # striped upper end of the bracket: dash-dot, same hue family
            st = dict(color=SYS_COLOR[sysname], marker="s", label=SYS_LABEL[sysname])
            ax.plot([p[0] for p in pts], [p[1] for p in pts], "-.", **st)
        else:
            st = _ps.style_line(sysname) if _ps else dict(color=SYS_COLOR[sysname], marker="o", label=SYS_LABEL[sysname])
            ax.plot([p[0] for p in pts], [p[1] for p in pts], "-", **st)
        for m, v in pts: ax.text(m, v * 1.03, f"{v:.0f}", ha="center", fontsize=5.5, color=st["color"])
    ax.set_xscale("log", base=2); ax.set_xticks([4, 8, 16, 32]); ax.set_xticklabels([4, 8, 16, 32])
    ax.set_xlabel("microbatch (LLaMA-MoE, EP=16)", fontsize=7); ax.set_ylabel("iteration (ms)", fontsize=7); ax.tick_params(labelsize=6)
    ax.legend(fontsize=5.5, frameon=False, loc="upper left"); ax.grid(alpha=0.3)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_mb.png")); print("wrote fig_mb.png")

def ladder():
    """R3: the cabling x dim-order 2x2 at EP=32 (dse_cabling_2x2.csv), plus the quoted port-map row
    at its zero-timeout buffer, with the queued NVL72 and the bound as reference lines."""
    rows = load("dse_cabling_2x2")
    cells = {(r["cabling"], str(r["dim_a2a"])): r for r in rows}
    fig, ax = plt.subplots(figsize=(3.4, 3.6), dpi=200)
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
            ax.axhline(v, color=SYS_COLOR["nvl64_pkt"], lw=0.9); ax.text(len(order) + 0.45, v * 1.02, f"NVL72 queued {v:.0f}", color=SYS_COLOR["nvl64_pkt"], fontsize=5.5, ha="right")
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
    """R5: interconnect energy per iteration, broken down by tier (glass: electrical RDL / intra-panel
    optical / inter-panel optical; NVSwitch fabrics: in-domain NVLink / NIC) plus the static term
    (laser+tune per panel; NVSwitch idle power per GPU). Link tiers are drawn at the conservative pJ/bit
    end, with a tick at the favorable end; static hatched. Optional second panel: energy per token when
    tokens_per_iter.csv exists (model, ep, mb, tokens)."""
    g = load("power_tiers"); n = load("power_tiers_pkt")
    PRIMARY_GLASS = os.environ.get("PRIMARY_GLASS", "glassfb_800")
    eps = sorted({int(r["ep"]) for r in g} | {int(r["ep"]) for r in n})
    systems = ["glass", "nvl64_pkt_s1", "hgx8_pkt"]   # NVL72 = the striped model
    NAMES = {"glass": "Glass-FB", "nvl64_pkt_s1": "NVL72", "hgx8_pkt": "HGX-8"}
    TIER_COL = {"elec": "#2b6f7f", "opt": "#6aa9b5", "inter": "#b7d8de", "nvlink": "#4b3f8f", "nic": "#b7aee0", "static": "none"}
    TIER_COL_HGX = {"nvlink": "#c46a4a", "nic": "#efd3c6"}
    TIER_LAB = {"elec": "electrical RDL (distance-1)", "opt": "intra-panel optical (L1/L2)", "inter": "inter-panel optical ports",
                "nvlink": "in-domain NVLink", "nic": "scale-out NIC", "static": "static (laser+tune / NVSwitch idle)"}
    def glass_row(ep):
        return next((r for r in g if r["system"] == PRIMARY_GLASS and int(r["ep"]) == ep), None) or \
               next((r for r in g if r["system"] == "glassfb" and int(r["ep"]) == ep), None)
    def stacks(sysname, ep):
        """[(tier, J_lo, J_hi)] link tiers then static."""
        if sysname == "glass":
            r = glass_row(ep)
            if not r: return None, None
            rdl = float(r["rdl_pj_bit"]); glo, ghi = float(r["glass_pj_bit_lo"]), float(r["glass_pj_bit_hi"])
            be, bo, bi = float(r["bytes_elec"]), float(r["bytes_opt"]), float(r["bytes_inter"])
            tiers = [("elec", be * 8 * (rdl + glo) * 1e-12, be * 8 * (rdl + ghi) * 1e-12),   # RDL tier carries +1 pJ/bit RDL on top of the glass bracket? see energy_model.md
                     ("opt", bo * 8 * glo * 1e-12, bo * 8 * ghi * 1e-12),
                     ("inter", bi * 8 * glo * 1e-12, bi * 8 * ghi * 1e-12)]
            # scale the per-tier split so the tiers sum to the table's own link_J_iter (the table is authoritative)
            lo_sum = sum(t[1] for t in tiers); hi_sum = sum(t[2] for t in tiers)
            L_lo, L_hi = float(r["link_J_iter_lo"]), float(r["link_J_iter_hi"])
            tiers = [(k, a * L_lo / lo_sum, b * L_hi / hi_sum) for k, a, b in tiers]
            st = float(r.get("static_J_iter") or 0)
            return tiers, (st, st)
        r = next((r for r in n if r["system"] == sysname and int(r["ep"]) == ep), None)
        if not r: return None, None
        nlo, nhi = float(r["nvlink_pj_bit_lo"]), float(r["nvlink_pj_bit_hi"]); nic = float(r["nic_pj_bit"])
        bd, bn = float(r["bytes_in_domain"]), float(r["bytes_nic"])
        hd, hc = float(r.get("hops_in_domain") or 1), float(r.get("hops_cross") or 1)
        tiers = [("nvlink", bd * hd * 8 * nlo * 1e-12, bd * hd * 8 * nhi * 1e-12), ("nic", bn * hc * 8 * nic * 1e-12, bn * hc * 8 * nic * 1e-12)]
        lo_sum = sum(t[1] for t in tiers); hi_sum = sum(t[2] for t in tiers)
        L_lo, L_hi = float(r["link_J_iter_lo"]), float(r["link_J_iter_hi"])
        tiers = [(k, a * L_lo / lo_sum, b * L_hi / hi_sum) for k, a, b in tiers]
        return tiers, (float(r["static_J_iter_lo"]), float(r["static_J_iter_hi"]))
    # optional per-token row
    tok = {}
    tp = os.path.join(RES, "tokens_per_iter.csv")
    if os.path.exists(tp):
        for t in csv.DictReader(open(tp)):
            v = t.get("tokens_per_iter") or t.get("tokens") or ""
            if str(t.get("mb") or "8") == "8" and v.strip(): tok[int(t["ep"])] = float(v)
    if len(tok) < 2: tok = {}
    ncol = len(eps); nrow = 3 if tok else 2
    fig, axes = plt.subplots(nrow, ncol, figsize=(7.0, 2.3 * nrow), dpi=200, sharey=False, squeeze=False)
    drawn = set()
    HUE = {"glass": "#2b6f7f", "nvl64_pkt_s1": "#4b3f8f", "hgx8_pkt": "#c46a4a"}
    for j, ep in enumerate(eps):
        a1 = axes[0][j]; a2 = axes[1][j]
        for x, sysname in enumerate(systems):
            tiers, st = stacks(sysname, ep)
            if tiers is None: continue
            # row 1: link energy by tier, linear, at the conservative pJ/bit end; tick = favorable end
            bottom = 0.0
            for k, lo, hi in tiers:
                col = TIER_COL_HGX[k] if (sysname == "hgx8_pkt" and k in TIER_COL_HGX) else TIER_COL[k]
                key = (k, sysname == "hgx8_pkt")
                lab = {("nvlink", False): "in-domain NVLink (NVL72)", ("nic", False): "scale-out NIC (NVL72)",
                       ("nvlink", True): "in-domain NVLink (HGX-8)", ("nic", True): "scale-out NIC (HGX-8)"}.get(key, TIER_LAB[k])
                a1.bar(x, hi, bottom=bottom, width=0.66, color=col, edgecolor="white", lw=0.4,
                       label=lab if key not in drawn else None); drawn.add(key)
                bottom += hi
            link_lo = bottom_lo = sum(t[1] for t in tiers)
            a1.plot([x - 0.33, x + 0.33], [link_lo, link_lo], color="black", lw=0.8)
            a1.text(x, bottom * 1.02, f"{link_lo:.0f}–{bottom:.0f}", ha="center", va="bottom", fontsize=6.5)
            # row 2: link vs static vs total, log scale, grouped
            tot_lo, tot_hi = link_lo + st[0], bottom + st[1]
            a2.bar(x - 0.22, bottom, width=0.2, color=HUE[sysname], label="link (bytes moved)" if "l2" not in drawn else None); drawn.add("l2")
            a2.bar(x, max(st[1], 1e-3), width=0.2, facecolor="white", edgecolor=HUE[sysname], hatch="////", lw=0.6,
                   label="static (idle power x iteration)" if "s2" not in drawn else None); drawn.add("s2")
            a2.bar(x + 0.22, tot_hi, width=0.2, color="#c9ced2", label="total" if "t2" not in drawn else None); drawn.add("t2")
            a2.text(x + 0.22, tot_hi * 1.15, f"{tot_lo:.0f}–{tot_hi:.0f}", ha="center", va="bottom", fontsize=6.2)
            if tok.get(ep):
                a3 = axes[2][j]
                mj_lo, mj_hi = tot_lo / tok[ep] * 1e3, tot_hi / tok[ep] * 1e3
                a3.bar(x, mj_hi, width=0.62, color="#9aa5ad", alpha=0.5); a3.bar(x, mj_lo, width=0.62, color=HUE[sysname])
                a3.text(x, mj_hi * 1.02, f"{mj_lo:.2f}–{mj_hi:.2f}", ha="center", va="bottom", fontsize=4.6)
        a1.set_title(f"EP={ep}", fontsize=9.5)
        a2.set_yscale("log")
        for ax in axes[:, j]:
            ax.set_xticks(range(len(systems))); ax.set_xticklabels([NAMES[s_] for s_ in systems], fontsize=8, rotation=30, ha="right")
            ax.tick_params(labelsize=7.5); ax.grid(alpha=0.25, axis="y")
        a1.set_ylim(0, a1.get_ylim()[1] * 1.18); a2.set_ylim(a2.get_ylim()[0], a2.get_ylim()[1] * 4)
        for ax in axes[:-1, j]: ax.set_xticklabels([])
    axes[0][0].set_ylabel("link energy per iteration (J)", fontsize=8.5)
    axes[1][0].set_ylabel("energy per iteration (J), log", fontsize=8.5)
    if tok: axes[2][0].set_ylabel("energy per token (mJ)", fontsize=6.5)
    h1, l1 = axes[0][0].get_legend_handles_labels(); h2, l2 = axes[1][0].get_legend_handles_labels()
    fig.legend(h1 + h2, l1 + l2, fontsize=7.5, frameon=False, loc="lower center", ncol=4, bbox_to_anchor=(0.5, -0.005), handlelength=1.6, columnspacing=1.0)
    fig.tight_layout(pad=0.3, rect=(0, 0.09 if not tok else 0.07, 1, 1)); fig.savefig(f("fig_energy.png")); print("wrote fig_energy.png")

def calib():
    """R-calib: NVSwitch model as an 8-GPU HGX H100 under a synthetic all-to-all (calib_nvswitch.csv:
    variant, msg_bytes, k, q, T_us, egress_GBps, efficiency, rtos, drops, quotable). Left: efficiency
    vs message size per variant, quoted rung solid / others hollow, with the DeepEP intra-node EP=8
    band (71-82% of line rate) as the large-message target. Right: completion time vs message size
    with the published small-message floor band (45-85 us)."""
    rows = load("calib_nvswitch")
    for r in rows:
        r["msg_bytes"] = float(r["msg_bytes"]); r["T_us"] = float(r["T_us"]); r["efficiency"] = float(r["efficiency"])
    variants = sorted({r["variant"] for r in rows})
    VLAB = {"s18": "pinned (18 x 25 GB/s, paper rows)", "s1": "striped (1 x 450 GB/s)"}
    VCOL = {"s18": "#7a0177", "s1": "#b06fc0"}
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(7.0, 3.2), dpi=200)
    a1.axhspan(0.71, 0.82, color="#d95f0e", alpha=0.18, lw=0, label="DeepEP, measured (71-82%)")
    a2.axhspan(45, 85, color="#d95f0e", alpha=0.18, lw=0, label="measured floor (45-85 us)")
    for v in variants:
        sub = [r for r in rows if r["variant"] == v]
        # Among quotable rows take the FIRST rung (lowest k), never the fastest:
        # the rule is the vanishing point of the timeouts, and a tiebreak on T_us
        # quietly reports the fastest clean rung instead whenever an upstream pass
        # has marked more than one row quotable.
        best = {}
        for r in sub:
            k = r["msg_bytes"]; cur = best.get(k)
            if cur is None or (r["_quotable"] and not cur["_quotable"]) or (
                    r["_quotable"] == cur["_quotable"] and
                    ((int(r["k"]), r["T_us"]) < (int(cur["k"]), cur["T_us"]) if r["_quotable"]
                     else r["T_us"] < cur["T_us"])):
                best[k] = r
        for k, r in best.items():
            n = sum(1 for x in sub if x["msg_bytes"] == k and x["_quotable"])
            if n > 1:
                print("  WARNING calib %s M=%d: %d quotable rungs, rule allows one; "
                      "drew the first (k=%s)" % (v, int(k), n, r["k"]))
        pts = sorted(best.values(), key=lambda r: r["msg_bytes"])
        col = VCOL.get(v, "#999"); lab = VLAB.get(v, v)
        a1.plot([r["msg_bytes"] for r in pts], [r["efficiency"] for r in pts], "-", color=col, lw=1.4, label=lab)
        a2.plot([r["msg_bytes"] for r in pts], [r["T_us"] for r in pts], "-", color=col, lw=1.4, label=lab)
        for ax, key in ((a1, "efficiency"), (a2, "T_us")):
            for r in pts:
                ax.plot(r["msg_bytes"], r[key], marker="o", ms=4, color=col, markerfacecolor=col if r["_quotable"] else "white")
    # optional third curve: SimAI (hardware-validated simulator) on its stock DGX-H100 topology
    sp = os.path.join(RES, "simai_calib.csv")
    if os.path.exists(sp):
        srows = sorted(csv.DictReader(open(sp)), key=lambda r: float(r["msg_bytes"]))
        ver = (srows[0].get("simai_version") or "").strip() if srows else ""
        lab = "SimAI (aggregate-bandwidth NVSwitch model" + (f", {ver}" if ver else "") + ")"
        a1.plot([float(r["msg_bytes"]) for r in srows], [float(r["efficiency"]) for r in srows], "^--", color="#1b7f3b", lw=1.2, ms=4, label=lab)
        a2.plot([float(r["msg_bytes"]) for r in srows], [float(r["T_us"]) for r in srows], "^--", color="#1b7f3b", lw=1.2, ms=4, label=lab)
        print(f"[calib] SimAI overlay: {len(srows)} points")
    for ax in (a1, a2):
        ax.set_xscale("log", base=2); ax.set_xlabel("bytes per (src,dst) pair", fontsize=7); ax.tick_params(labelsize=6); ax.grid(alpha=0.3, which="both")
    a1.set_ylabel("egress / 450 GB/s line rate", fontsize=7); a1.set_ylim(0, 1.05); a1.legend(fontsize=5.5, frameon=False, loc="upper left")
    a2.set_yscale("log"); a2.set_ylabel("all-to-all completion (us)", fontsize=7); a2.legend(fontsize=5.5, frameon=False, loc="upper left")
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_calib.png")); print("wrote fig_calib.png")

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
    # TAIL_ONLY="nvl64_pkt:16,glassfb:64" selects a subset (the paper's two-ladder panel); OUT name follows
    only = os.environ.get("TAIL_ONLY")
    if only:
        want = [(t.split(":")[0], int(t.split(":")[1])) for t in only.split(",")]
    panels = [(k, sorted(groups[k])) for k in want if k in groups and len(groups[k]) >= 2]
    if not panels: sys.exit("buffer_sweeps: no multi-point sweeps")
    fig, axes = plt.subplots(1, len(panels), figsize=((7.16 if len(panels) > 2 else 3.6), (2.2 if len(panels) > 2 else 3.2)), dpi=200)
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
    name = "fig_tail2.png" if only else "fig_tail.png"
    fig.tight_layout(pad=0.3, rect=(0, 0.03, 1, 1)); fig.savefig(f(name)); print(f"wrote {name}")

def boundary():
    """Price of the boundary. (a) share of each fabric's hop-bytes that cross a domain boundary
    (glass: inter-panel ports; NVSwitch fabrics: NICs), per EP. (b) the expert all-to-all's share of
    the critical path against the time those cross-domain bytes alone need on the fabric's own
    cross-domain tier (bytes / (GPUs x per-GPU cross-domain bandwidth)): one line, three prices.
    Sources: power_tiers(.csv/_pkt.csv) hop-bytes, decomp_critpath.csv expert_a2a_ms, Table III port rates."""
    g = load("power_tiers"); n = load("power_tiers_pkt")
    d = list(csv.DictReader(open(os.path.join(RES, "decomp_critpath.csv"))))
    PRIMARY_GLASS = os.environ.get("PRIMARY_GLASS", "glassfb_800")
    XBW = {"glass": 800.0, "nvl64_pkt_s1": 100.0, "hgx8_pkt": 50.0}   # GB/s per GPU on the cross-domain tier (Table III)
    NAMES = {"glass": "Glass-FB", "nvl64_pkt_s1": "NVL72", "hgx8_pkt": "HGX-8"}
    HUE = {"glass": "#2b6f7f", "nvl64_pkt_s1": "#4b3f8f", "hgx8_pkt": "#c46a4a"}
    MK = {16: "o", 32: "s", 64: "D", 128: "^"}
    eps = [16, 32, 64, 128]
    def row(sysname, ep):
        if sysname == "glass":
            return next((r for r in g if r["system"] == PRIMARY_GLASS and int(r["ep"]) == ep), None)
        return next((r for r in n if r["system"] == sysname and int(r["ep"]) == ep), None)
    def a2a(sysname, ep):
        key = PRIMARY_GLASS if sysname == "glass" else sysname
        c = [x for x in d if x["label"].startswith(key + " EP=%d" % ep) and re.search(r"mb=(8|-)", x["label"])]
        if not c: c = [x for x in d if x["label"].startswith(key + " EP=%d" % ep)]
        if not c: return None
        c.sort(key=lambda x: abs(float(x["makespan_ms"]) - float(row(sysname, ep)["makespan_ms"])))
        return float(c[0]["expert_a2a_ms"])
    pts = {}
    for sname in XBW:
        for ep in eps:
            r = row(sname, ep)
            if not r: continue
            if sname == "glass":
                cross = float(r["bytes_inter"]); tot = float(r["bytes_elec"]) + float(r["bytes_opt"]) + cross
            else:
                cross = float(r["bytes_nic"]); tot = float(r["bytes_in_domain"]) + cross
            gpus = int(float(r["nodes"]))
            pts[(sname, ep)] = dict(share=100 * cross / tot, tier_ms=cross / (gpus * XBW[sname]) / 1e6, a2a=a2a(sname, ep))
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(3.45, 4.3), dpi=200, gridspec_kw=dict(height_ratios=[0.85, 1]))
    # (a) share bars
    w = 0.26; xs = list(range(len(eps)))
    for j, sname in enumerate(XBW):
        vals = [pts.get((sname, ep), {}).get("share") for ep in eps]
        for i, v in enumerate(vals):
            if v is None: continue
            ax1.bar(i + (j - 1) * w, v, w * 0.92, color=HUE[sname], label=NAMES[sname] if i == 0 else None)
            ax1.text(i + (j - 1) * w, v + 1.2, "%.0f" % v, ha="center", va="bottom", fontsize=5.6, color="#333")
    ax1.set_xticks(xs); ax1.set_xticklabels(["EP=%d" % e for e in eps]); ax1.set_ylim(0, 100)
    ax1.set_ylabel("hop-bytes crossing a domain (%)"); ax1.legend(frameon=False, fontsize=6.5, loc="upper left")
    ax1.set_title("(a) how much traffic leaves the domain", fontsize=7.5, loc="left")
    ax1.axvline(2.5, color="#999", lw=0.6, ls=(0, (3, 2)))
    ax1.text(2.52, 96, "NVL boundary", fontsize=5.8, color="#666", ha="left", va="top")
    # (b) a2a on the critical path vs the cross-domain tier's own transfer time
    for sname in XBW:
        xx = [pts[(sname, ep)]["tier_ms"] for ep in eps if (sname, ep) in pts and pts[(sname, ep)]["a2a"] is not None]
        yy = [pts[(sname, ep)]["a2a"] for ep in eps if (sname, ep) in pts and pts[(sname, ep)]["a2a"] is not None]
        ee = [ep for ep in eps if (sname, ep) in pts and pts[(sname, ep)]["a2a"] is not None]
        ax2.plot(xx, yy, color=HUE[sname], lw=0.8, alpha=0.5, zorder=2)
        for x, y, ep in zip(xx, yy, ee):
            ax2.scatter([x], [y], marker=MK[ep], s=22, color=HUE[sname], edgecolor="white", lw=0.5, zorder=3)
    for ep in eps:
        ax2.scatter([], [], marker=MK[ep], s=18, color="#555", label="EP=%d" % ep)
    lim = [0.3, 300]
    ax2.plot(lim, lim, color="#bbb", lw=0.7, ls=(0, (3, 2)), zorder=1)
    ax2.text(lim[1] * 0.9, 2.4, "A2A = cross-domain transfer\ntime (lower bound)", fontsize=5.4, color="#888", ha="right", va="bottom")
    ax2.set_xscale("log"); ax2.set_yscale("log"); ax2.set_xlim(*lim); ax2.set_ylim(2, 300)
    ax2.set_xlabel("cross-domain bytes / cross-domain bandwidth (ms)")
    ax2.set_ylabel("expert A2A on critical path (ms)")
    ax2.legend(frameon=False, fontsize=6, loc="upper left", handletextpad=0.2, ncol=2, columnspacing=0.8)
    ax2.set_title("(b) what that traffic costs", fontsize=7.5, loc="left")
    for ax in (ax1, ax2):
        ax.spines["top"].set_visible(False); ax.spines["right"].set_visible(False); ax.tick_params(labelsize=6.5)
    for (sname, ep), v in sorted(pts.items()):
        print("  %-12s EP=%3d share=%5.1f%%  tier=%7.2f ms  a2a=%s" % (NAMES[sname], ep, v["share"], v["tier_ms"], v["a2a"]))
    fig.tight_layout(pad=0.3, h_pad=1.0); fig.savefig(f("fig_boundary.png")); fig.savefig(f("fig_boundary.pdf")); print("wrote fig_boundary.png")

def loadfig():
    """Load (Sec. dse): EP=16 iteration against microbatch as lines (MixNet Fig. 12a style), Glass-FB
    (200G/lane) and NVL72, each normalised to that fabric's own mb=4 quoted row (user 2026-09-08:
    lines, no compute/A2A split, normalised y)."""
    rows = load("cliff_all")
    def quoted_mb(sysname, mb):
        c = [r for r in rows if r["system"] == sysname and r.get("ep") == 16 and r.get("mb") == mb and r["_quotable"] and r.get("link_rate_fixed") == "yes"]
        return min((r["makespan_ms"] for r in c), default=None)
    STY = {"glassfb_800": dict(color="#2b6f7f", marker="o", label="Glass-FB"), "nvl64_pkt_s1": dict(color="#4b3f8f", marker="s", label="NVL72")}
    fig, ax = plt.subplots(figsize=(3.45, 2.3), dpi=200)
    mbs = [4, 8, 16, 32]
    for sysname, st in STY.items():
        ref = quoted_mb(sysname, 4)
        pts = [(mb, quoted_mb(sysname, mb) / ref) for mb in mbs if ref and quoted_mb(sysname, mb) is not None]
        ax.plot([p for p, _ in pts], [v for _, v in pts], "-", lw=1.3, ms=4.5, **st)
        for mb, v in pts:
            ax.annotate("%.2f" % v, (mb, v), textcoords="offset points", xytext=(0, 5 if sysname == "nvl64_pkt_s1" else -10), ha="center", fontsize=6.5, color=st["color"])
    ax.set_xscale("log", base=2); ax.set_xticks(mbs); ax.set_xticklabels([str(m) for m in mbs]); ax.minorticks_off()
    ax.set_xlabel("microbatch (LLaMA-MoE, EP=16)", fontsize=8.5); ax.set_ylabel("normalized iteration time", fontsize=8.5)
    ax.set_ylim(0.95, 1.36); ax.tick_params(labelsize=7.5)
    ax.legend(frameon=False, fontsize=7.5, loc="upper left"); ax.grid(lw=0.4, alpha=0.4)
    ax.spines["top"].set_visible(False); ax.spines["right"].set_visible(False)
    fig.tight_layout(pad=0.3); fig.savefig(f("fig_load.png")); fig.savefig(f("fig_load.pdf")); print("wrote fig_load.png")

if __name__ == "__main__":
    which = sys.argv[1:] or ["all"]
    fns = {"cliff": cliff, "decomp": decomp, "beyond": beyond, "mb": mb, "ladder": ladder, "energy": energy, "tail": tail, "calib": calib, "boundary": boundary, "load": loadfig}
    for w in (fns if "all" in which else which):
        try: fns[w]()
        except SystemExit as e: print("skip:", e)
