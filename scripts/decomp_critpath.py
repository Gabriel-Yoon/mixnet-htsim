#!/usr/bin/env python3
"""Iteration decomposed by task class ALONG THE CRITICAL PATH, not by summing tasks.

Summing task durations by class answers a different question: tasks overlap, so
the sum exceeds the iteration and the shares are not shares of anything. The
critical path is what the makespan is made of.

Both inputs are already in the run logs, so no rebuild is needed:

  ffapp.cpp:1193   "<app> finished task:<id>, nfin N ntot M name: <name> type <t> now <ps>"
  ffapp.cpp:1201   "<from> -> Task <to> counter at <c> name: <name> task type:<t>"

giving a finish time and class per task, and the dependency edges. A task's
contribution to the critical path is

    finish(T) - max over predecessors p of finish(p)

which is exactly the time it added, and the contributions along the path sum to
the makespan by construction -- a property checked and reported, not assumed.

start_time is not logged, but in this event-driven model a task starts when it
becomes ready (ready_time = predecessor's finish, ffapp.cpp:1204), so the
contribution above already contains any wait. Idle is therefore not separable
from task time here, and this script does NOT invent a split: it reports the
contribution per class and says so.

The A2A class is likewise NOT split intra-/cross-panel in time. One all-to-all
task contains both, and apportioning its critical-path time by byte share would
be an assumption dressed as a measurement. The byte split is reported alongside,
from the flow log, as a separate column.
"""
import collections, csv, os, re, sys

OUT = ("/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/experiments/results/paper/decomp_critpath.csv")
ROWS = []

TYPE_NAMES = {
    0: "compute_fwd", 1: "compute_bwd", 2: "comm", 3: "update", 4: "barrier",
    5: "nominal_comm", 6: "pp_p2p", 7: "sub_allreduce", 8: "dp_allreduce",
    9: "tp_allreduce", 10: "allreduce", 11: "reduce_scatter", 12: "all_gather",
    13: "expert_a2a",
}
CLASS_OF = {
    "compute_fwd": "compute", "compute_bwd": "compute", "update": "compute",
    "pp_p2p": "pp_p2p",
    "dp_allreduce": "dp_allreduce", "sub_allreduce": "dp_allreduce",
    "allreduce": "dp_allreduce", "tp_allreduce": "dp_allreduce",
    "reduce_scatter": "dp_allreduce", "all_gather": "dp_allreduce",
    "expert_a2a": "expert_a2a",
    "comm": "other", "nominal_comm": "other", "barrier": "other",
}

RE_FIN = re.compile(r"finished task:(\d+),.*?type (\d+) now (\d+)")
RE_EDGE = re.compile(r"^(\d+) -> Task (\d+) counter at")
# The run's OWN reported makespan. A still-running log yields a perfectly
# well-formed but partial critical path -- glass EP=64 read 33.547 ms from a
# log whose completed siblings are 52-61 ms. Existence of task records is not
# evidence the run finished, so the reconstruction is checked against what the
# run itself reported and a mismatch is refused rather than published.
RE_ITER = re.compile(r"finished one iter.*?now (\d+)")


def parse(path):
    finish, ttype, preds = {}, {}, collections.defaultdict(set)
    with open(path, errors="replace") as fh:
        for line in fh:
            m = RE_FIN.search(line)
            if m:
                tid = int(m.group(1))
                finish[tid] = int(m.group(3))
                ttype[tid] = int(m.group(2))
                continue
            m = RE_EDGE.match(line)
            if m:
                preds[int(m.group(2))].add(int(m.group(1)))
    return finish, ttype, preds


def critical_path(finish, preds):
    if not finish:
        return []
    end = max(finish, key=lambda t: finish[t])
    path, seen = [], set()
    cur = end
    while cur is not None and cur not in seen:
        seen.add(cur)
        ps = [p for p in preds.get(cur, ()) if p in finish]
        best = max(ps, key=lambda p: finish[p]) if ps else None
        base = finish[best] if best is not None else 0
        path.append((cur, finish[cur] - base))
        cur = best
    return list(reversed(path))


def bytes_split(flowlog, psize=16):
    intra = cross = 0
    if not flowlog or not os.path.exists(flowlog):
        return None
    with open(flowlog) as fh:
        for line in fh:
            f = line.split()
            if len(f) != 4:
                continue
            s, d, b = int(f[1]), int(f[2]), int(f[3])
            if s // psize == d // psize:
                intra += b
            else:
                cross += b
    return intra, cross


def run(label, log, flowlog=None):
    if not os.path.exists(log):
        print("%-26s (log not present yet)" % label); return None
    reported = None
    with open(log, errors="replace") as fh:
        for line in fh:
            m = RE_ITER.search(line)
            if m:
                reported = int(m.group(1))
    if reported is None:
        print("%-26s SKIPPED: no completed iteration in the log (still running?)" % label)
        return None
    finish, ttype, preds = parse(log)
    path = critical_path(finish, preds)
    if not path:
        print("%-16s no task records in %s" % (label, log)); return None
    per = collections.Counter()
    for tid, contrib in path:
        cls = CLASS_OF.get(TYPE_NAMES.get(ttype.get(tid, -1), "?"), "other")
        per[cls] += contrib
    total = sum(per.values())
    if total != reported:
        print("%-26s SKIPPED: critical path sums to %.3f ms but the run reports %.3f ms"
              % (label, total / 1e9, reported / 1e9))
        return None
    print("\n=== %s ===" % label)
    print("  critical path: %d tasks, %d distinct tasks logged, makespan %.3f ms"
          % (len(path), len(finish), total / 1e9))
    for cls, v in sorted(per.items(), key=lambda kv: -kv[1]):
        print("    %-16s %9.3f ms  (%5.1f%%)" % (cls, v / 1e9, 100.0 * v / total))
    bs = bytes_split(flowlog)
    if bs:
        intra, cross = bs
        tot = intra + cross
        print("    [all flows, not only the path] intra-panel %.3f TB (%.1f%%), "
              "cross-panel %.3f TB (%.1f%%)"
              % (intra / 1e12, 100.0 * intra / tot, cross / 1e12, 100.0 * cross / tot))
    ROWS.append(dict(
        paper_ref="decomp", label=label, log=os.path.basename(log),
        path_tasks=len(path), tasks_logged=len(finish),
        makespan_ms="%.3f" % (total / 1e9),
        compute_ms="%.3f" % (per.get("compute", 0) / 1e9),
        expert_a2a_ms="%.3f" % (per.get("expert_a2a", 0) / 1e9),
        dp_allreduce_ms="%.3f" % (per.get("dp_allreduce", 0) / 1e9),
        pp_p2p_ms="%.3f" % (per.get("pp_p2p", 0) / 1e9),
        other_ms="%.3f" % (per.get("other", 0) / 1e9),
        intra_TB=("%.3f" % (bs[0] / 1e12)) if bs else "",
        cross_TB=("%.3f" % (bs[1] / 1e12)) if bs else "",
        note=("critical-path contribution per class, finish(T) minus max predecessor finish; "
              "contributions sum to the makespan by construction and that is checked, not assumed. "
              "Idle is NOT separable: start_time is not logged and a task starts when ready, so any "
              "wait is inside its contribution. The A2A class is NOT split intra/cross in TIME -- one "
              "task carries both and apportioning by byte share would be an assumption; the byte "
              "split is a separate column over all flows, not only those on the path")))
    return per, total


if __name__ == "__main__":
    DC = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter"
    # EP=16, the quoted rows (86.750 and 130.797); taken from mb_logs so both come
    # from the same script and job rather than two unrelated sweeps.
    run("glassfb EP=16 q=1064", os.path.join(DC, "mb_logs/glass_mb8_q1064.log"),
        os.path.join(DC, "tier_logs/tier_ep16.flowlog"))
    run("nvl64_pkt EP=16 q=544", os.path.join(DC, "mb_logs/nvl64_mb8_q544.log"))
    # EP=32, the quoted rows
    run("glassfb EP=32 q=2133", os.path.join(DC, "gtk_logs/gt_k4.log"),
        os.path.join(DC, "tier_logs/tier_ep32.flowlog"))
    run("nvl64_pkt EP=32 q=1088", os.path.join(DC, "pktvt_logs/nvl64_pkt_ep32_q1088.log"))
    # EP=64, picked up when the walks produce a zero-timeout row. A log that
    # exists but has no completed iteration is skipped by run() itself, so a
    # still-running cell cannot contribute a half-built path.
    import glob as _g
    for f in sorted(_g.glob(os.path.join(DC, "gt64x_logs/k*.log"))):
        run("glassfb EP=64 " + os.path.basename(f).replace(".log", ""), f)
    for f in sorted(_g.glob(os.path.join(DC, "pktvt_logs/nvl64_pkt_ep64_q*.log"))):
        run("nvl64_pkt EP=64 " + os.path.basename(f).split("_")[-1].replace(".log", ""), f)
    # The striping control's quoted rows, so R2 can show the fabric share at BOTH
    # ends of the bracket. Only the quoted cell of each walk is decomposed -- the
    # rungs below it have timeouts, and a critical path through retransmissions
    # measures the timeout, not the fabric.
    for ep, q in ((16, 2400), (32, 4800), (64, 9600)):
        f = os.path.join(DC, "stripe_logs", "*_ep%d_q%d.log" % (ep, q))
        for g in sorted(_g.glob(f)):
            run("nvl64_pkt_s1 EP=%d q=%d" % (ep, q), g)

    # Post-fix quoted rows, driven by the collector's own verdict rather than a
    # hardcoded list: whatever collect_rungs quoted is what R2 should decompose.
    # Each row's stdout log is found from its rung tag; a quoted row with no log is
    # reported by run() rather than skipped, because "absent because missing" and
    # "absent because fine" look identical in a summary table.
    import csv as _csv
    _post = os.path.join(DC, "../../../experiments/results/paper/cliff_postfix.csv")
    if os.path.exists(_post):
        for _r in _csv.DictReader(open(_post, newline="")):
            if _r.get("quotable") != "yes":
                continue
            _tag = (_r.get("source") or "").replace(".csv", "")
            for _f in sorted(_g.glob(os.path.join(DC, "rung_logs", _tag + "_*.log"))):
                run("%s EP=%s mb=%s %s" % (_r.get("system"), _r.get("ep"),
                                           _r.get("mb") or "-", _tag), _f)

    hgx = os.path.join(DC, "pktvt_logs")
    import glob as _g
    for f in sorted(_g.glob(os.path.join(hgx, "hgx8_pkt_ep32_q*.log"))):
        run("hgx8_pkt EP=32 " + os.path.basename(f).split("_")[-1].replace(".log", ""), f)
    if ROWS:
        with open(OUT, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(ROWS[0].keys()))
            w.writeheader(); w.writerows(ROWS)
        print("\nwrote", OUT)
