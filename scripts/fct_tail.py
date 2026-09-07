#!/usr/bin/env python3
"""Payload FCT tail for a run, read from its own output directory, or refused.

  python3 scripts/fct_tail.py <stdout-log> [<stdout-log> ...]

Each run's stdout names its output directory ("Log directory is: ..."), so a tail
can be attributed to a cell without the caller remembering which is which.

WHAT THIS REFUSES, AND WHY IT HAS TO. Until fbcece7 the runners' _logdir
incremented a counter inside $(_logdir)'s subshell, so the increment never reached
the parent and every cell of a job wrote into ONE directory. A post-hoc reader
then finds only whichever cell wrote last and would hand that tail to all of them.
So the directory is checked against every log that claims it: if two logs name the
same directory, the LAST writer is the only one whose tail is real, and the others
are refused by name rather than given a plausible number.

That check is what makes a returned tail worth quoting. A blank is recoverable; a
tail attributed to the wrong buffer is not.

The tail is the PAYLOAD tail -- flows larger than one MSS -- which is the
convention used everywhere else here: the zero-byte all-to-all flows are floored
to one packet and would otherwise crowd the distribution with records that moved
nothing. Both counts are reported so the split is visible.
"""
import os, re, sys

MSS = 1436
RE_LOGDIR = re.compile(r"Log directory is:\s*(\S+)")
RE_ITER = re.compile(r"finished one iter.*?now (\d+)")
DC = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly/src/clos/datacenter"


def scan(log):
    """(logdir, makespan_ms, timeouts) from a run's stdout."""
    ld, ps, rtos = None, None, 0
    with open(log, errors="replace") as fh:
        for line in fh:
            if line.startswith("At "):
                rtos += 1
                continue
            if ld is None:
                m = RE_LOGDIR.search(line)
                if m:
                    ld = m.group(1)
                    continue
            if "finished one iter" in line:
                m = RE_ITER.search(line)
                if m:
                    ps = int(m.group(1))
    return ld, (ps / 1e9 if ps else None), rtos


def tail(fct_path):
    """(flows_total, flows_payload, mean, p50, p99, max) in ms, or None."""
    vals, total = [], 0
    try:
        with open(fct_path, errors="replace") as fh:
            for line in fh:
                if not line.startswith("FCT "):
                    continue
                f = line.split()
                if len(f) < 5:
                    continue
                total += 1
                if float(f[3]) > MSS:
                    vals.append(float(f[4]))
    except OSError:
        return None
    if not vals:
        return (total, 0, None, None, None, None)
    vals.sort()
    n = len(vals)
    return (total, n, sum(vals) / n,
            vals[min(n - 1, int(n * 0.50))],
            vals[min(n - 1, int(n * 0.99))],
            vals[-1])


def main(logs):
    scanned = {}
    for lg in logs:
        if not os.path.exists(lg):
            print("%-44s MISSING" % os.path.basename(lg)); continue
        scanned[lg] = scan(lg)

    # who else claims each directory
    claims = {}
    for lg, (ld, _, _) in scanned.items():
        if ld:
            claims.setdefault(ld, []).append(lg)

    for lg in logs:
        if lg not in scanned:
            continue
        base = os.path.basename(lg)
        ld, ms, rtos = scanned[lg]
        if not ld:
            print("%-44s REFUSED: no logdir line" % base); continue
        sharers = claims.get(ld, [])
        if len(sharers) > 1:
            newest = max(sharers, key=lambda p: os.path.getmtime(p))
            if lg != newest:
                print("%-44s REFUSED: shares %s with %d other cell(s); %s wrote last"
                      % (base, os.path.basename(ld), len(sharers) - 1,
                         os.path.basename(newest)))
                continue
            note = " (shared dir; this cell wrote last)"
        else:
            note = ""
        d = ld if os.path.isabs(ld) else os.path.join(DC, ld.lstrip("./"))
        t = tail(os.path.join(d, "fct_util_out.txt"))
        if t is None:
            print("%-44s REFUSED: no fct_util_out.txt in %s" % (base, os.path.basename(ld)))
            continue
        tot, npay, mean, p50, p99, mx = t
        if not npay:
            print("%-44s no payload flows (%d records)" % (base, tot)); continue
        print("%-44s ms=%-9s rtos=%-7d flows=%d/%d  mean=%.4f p50=%.4f p99=%.4f max=%.4f%s"
              % (base, ("%.3f" % ms) if ms else "-", rtos, npay, tot, mean, p50, p99, mx, note))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    main(sys.argv[1:])
