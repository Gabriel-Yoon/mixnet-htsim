#!/usr/bin/env python3
"""Per-layer comp_time breakdown of the steady decode iteration, EP32 vs EP64.

Answers "why does glass TPOT drop from EP32 to EP64?" by running a short serving
job per EP (glass-FB, TP=1), then parsing the generated trace files
($TMPDIR/llmservingsim_<pid>/trace/<hw>/<model>/instanceI_batchB.txt) and summing
comp_time by layer category for the MODAL (steady-decode) iteration. The delta
column shows exactly which layer family (attention / expert / dense / ...) changed.

Run on HPC (EP=64 OOMs the local 7.65GiB Docker):
  python scripts/trace_breakdown.py --eps 32 64 --model Qwen/Qwen3-235B-A22B \
      --hardware H100 --panel 4 4 --fixed-wg 5 --npu-mem-gb 1024
"""
import argparse, csv, glob, os, re, subprocess, sys, collections, statistics, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweep_panel_dse as S

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _category(layer_name):
    """Strip the trailing _<layernum> to get the layer family."""
    return re.sub(r'_\d+$', '', layer_name)


def parse_trace(path):
    """Return (total_comp_ns, {category: comp_ns}) for one trace file."""
    by_cat = collections.defaultdict(int)
    total = 0
    for line in open(path):
        f = line.split()
        if len(f) >= 2 and f[1].lstrip('-').isdigit() and not f[0].isdigit() \
           and f[0] not in ("EXPERT", "PIM", "COLOCATED"):
            t = int(f[1])
            by_cat[_category(f[0])] += t
            total += t
    return total, by_cat


def steady_breakdown(trace_dir):
    """Across instance0's decode traces, find the MODAL total comp_time (= the
    steady decode iteration) and return its per-category breakdown."""
    files = glob.glob(os.path.join(trace_dir, "instance0_batch*.txt"))
    if not files:
        # fall back to any instance
        files = glob.glob(os.path.join(trace_dir, "instance*_batch*.txt"))
    parsed = [parse_trace(f) for f in files]
    parsed = [p for p in parsed if p[0] > 0]
    if not parsed:
        return None, None, 0
    totals = [p[0] for p in parsed]
    # MODE on 0.1ms-binned totals (matches tpot_gt's steady-decode mode)
    binned = [round(t / 1e5) for t in totals]
    mode_bin = collections.Counter(binned).most_common(1)[0][0]
    rep = next(p for p in parsed if round(p[0] / 1e5) == mode_bin)
    return rep[0], rep[1], len(parsed)


def run_and_get_trace_dir(ep, args):
    tmp = os.path.join(args.tmp_root, f"tb_ep{ep}")
    if os.path.isdir(tmp):
        shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp, exist_ok=True)
    S.MODEL_NAME = args.model; S.HARDWARE = args.hardware; S.TP = 1
    S.NPU_MEM["mem_size"] = args.npu_mem_gb; S.NVL72_RACK = 64
    rows, cols = args.panel
    multi = ep > rows * cols
    cfg = S.make_panel_config(rows, cols, ep, wg_count=args.fixed_wg,
                              inter_bw=(args.inter_opt_bw if multi else 0.0))
    cfg_rel = os.path.join("configs", "cluster", f"_tb_glass_ep{ep}.json")
    import json
    json.dump(cfg, open(os.path.join(REPO, cfg_rel), "w"), indent=2)
    wl_rel, _ = S.make_workload(ep, args.n_per_inst, "controlled", args.isl, args.osl)
    out_csv = f"outputs/panel_dse/runs/_tb_glass_ep{ep}.csv"
    os.makedirs(os.path.join(REPO, "outputs", "panel_dse", "runs"), exist_ok=True)
    env = {**os.environ, "MOE_ALLTOALL": "1", "TMPDIR": tmp}
    cmd = ["python", "-m", "serving", "--cluster-config", cfg_rel, "--dtype", "bfloat16",
           "--block-size", "16", "--dataset", wl_rel, "--output", out_csv,
           "--max-num-seqs", str(args.n_per_inst + 4), "--log-level", "WARNING"]
    print(f"  [ep{ep}] running serving (osl={args.osl}) ...", flush=True)
    subprocess.run(cmd, cwd=REPO, env=env, timeout=args.timeout,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    hits = glob.glob(os.path.join(tmp, "llmservingsim_*", "trace", args.hardware, args.model))
    return hits[0] if hits else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eps", type=int, nargs="+", default=[32, 64])
    ap.add_argument("--model", default="Qwen/Qwen3-235B-A22B")
    ap.add_argument("--hardware", default="H100")
    ap.add_argument("--panel", type=int, nargs=2, default=[4, 4])
    ap.add_argument("--fixed-wg", type=int, default=5)
    ap.add_argument("--inter-opt-bw", type=float, default=512.0)
    ap.add_argument("--npu-mem-gb", type=int, default=1024)
    ap.add_argument("--n-per-inst", type=int, default=2)
    ap.add_argument("--isl", type=int, default=64)
    ap.add_argument("--osl", type=int, default=8)
    ap.add_argument("--tmp-root", default="/tmp/tb_trace")
    ap.add_argument("--timeout", type=int, default=3600)
    args = ap.parse_args()

    results = {}   # ep -> (total_ns, {cat: ns}, n_traces)
    for ep in args.eps:
        tdir = run_and_get_trace_dir(ep, args)
        if not tdir:
            print(f"  [ep{ep}] no trace dir found"); continue
        results[ep] = steady_breakdown(tdir)

    cats = sorted({c for _, bc, _ in results.values() if bc for c in bc})
    eps = [e for e in args.eps if e in results and results[e][1]]
    print("\n=== steady-decode per-layer comp_time (us) ===")
    hdr = f"{'layer':<22}" + "".join(f"{'ep'+str(e):>12}" for e in eps)
    if len(eps) == 2:
        hdr += f"{'delta(us)':>12}{'%chg':>8}"
    print(hdr)
    for c in cats:
        vals = [results[e][1].get(c, 0) / 1e3 for e in eps]  # ns -> us
        line = f"{c:<22}" + "".join(f"{v:>12.1f}" for v in vals)
        if len(eps) == 2:
            d = vals[1] - vals[0]
            pct = (d / vals[0] * 100) if vals[0] else 0
            line += f"{d:>12.1f}{pct:>7.0f}%"
        print(line)
    print("-" * len(hdr))
    tot = [results[e][0] / 1e3 for e in eps]
    line = f"{'TOTAL':<22}" + "".join(f"{v:>12.1f}" for v in tot)
    if len(eps) == 2:
        d = tot[1] - tot[0]
        line += f"{d:>12.1f}{(d/tot[0]*100 if tot[0] else 0):>7.0f}%"
    print(line)
    for e in eps:
        print(f"  ep{e}: {results[e][2]} decode traces parsed, modal total {tot[args.eps.index(e) if e in args.eps else 0]:.1f}us")


if __name__ == "__main__":
    main()
