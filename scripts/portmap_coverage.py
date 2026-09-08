#!/usr/bin/env python3
"""Does a port map cable every panel pair its workload actually uses?

This is the check the EP=128 DSE arm skipped, and skipping it cost twelve jobs at
four to five hours each. It is one set difference over two files already on disk:
no simulation, no binary, no cluster. It exists as a script so the next arm cannot
skip it by forgetting how.

A missing pair does not fail loudly at run time. The flow is RELAYED instead, the
row is written with status=blocked and relayed_pairs>0, and the makespan that comes
out is a real number for a fabric that is not the one named -- one such row read
19934.507 ms, which on a buffer-axis plot would have looked like a finding.

USAGE
    portmap_coverage.py <portmap> <hoplog-or-flowlog> <gpus-per-panel>

Panel pairs come from the (src, dst) columns of a hop or flow log, divided by the
panel size. That log is workload-determined and topology-independent -- ffapp emits
the same flows whichever fabric is loaded -- so a log captured on ANY panel geometry
lists the right node pairs; only the division into panels changes, and that is the
argument this script takes.
"""
import collections, os, sys


def pairs_from_log(path, psize):
    out = collections.Counter()
    with open(path) as fh:
        for line in fh:
            f = line.split()
            if len(f) < 3 or not f[1].lstrip("-").isdigit():
                continue
            s, d = int(f[1]), int(f[2])
            ps, pd = s // psize, d // psize
            if ps != pd:
                out[(min(ps, pd), max(ps, pd))] += 1
    return out


def pairs_from_map(path):
    out = set()
    with open(path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            f = line.split()
            if len(f) >= 2 and f[0].isdigit() and f[1].isdigit():
                a, b = int(f[0]), int(f[1])
                out.add((min(a, b), max(a, b)))
    return out


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2
    pm_path, log_path, psize = argv[1], argv[2], int(argv[3])
    for p in (pm_path, log_path):
        if not os.path.exists(p):
            print("MISSING: %s" % p)
            return 2
    used = pairs_from_log(log_path, psize)
    cabled = pairs_from_map(pm_path)
    missing = sorted(set(used) - cabled)
    unused = sorted(cabled - set(used))

    print("port map : %s" % os.path.basename(pm_path))
    print("traffic  : %s  (panel size %d)" % (os.path.basename(log_path), psize))
    print("  panel pairs used by traffic : %d" % len(used))
    print("  panel pairs cabled          : %d" % len(cabled))
    print("  cabled but unused           : %d" % len(unused))
    if missing:
        print("  NEEDED BUT NOT CABLED       : %d" % len(missing))
        for pq in missing[:24]:
            print("      (%d,%d)   %d flow(s) would be relayed" % (pq[0], pq[1], used[pq]))
        if len(missing) > 24:
            print("      ... and %d more" % (len(missing) - 24))
        print("REFUSE: every run on this map would be status=blocked and unquotable.")
        return 1
    print("OK: every pair the workload uses is cabled. Runs on this map can be quotable.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
