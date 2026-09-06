#!/usr/bin/env python3
"""Decompose an htsim glassfb run by link class (FRED Fig-10 style).

The simulator does not attribute exposed time per link class directly, but it
emits enough per-flow data to reconstruct it:

  flow_size: <bytes> src_node: <s> dst_node: <d>     (stdout, one per flow)
  FCT <s> <d> <bytes> <fct> <...> <util>             (logdir/fct_util_out.txt)

Given the panel mapping (panel = node // panel_size) every flow classifies as:
  same_node   s == d                      (no wire)
  intra_adj   same panel, grid distance 1  -> electrical RDL
  intra_far   same panel, distance >= 2    -> glass waveguide
  inter       different panel              -> optical fibre / gateway

Reports bytes and FCT distribution per class, which is what makes results like
"RTOs rose while makespan fell" legible: it shows which class absorbed the
traffic and which one became the new constraint.

WARNING -- pre-e2fc399 logs. The flow_size: line is emitted on the flow-creation
path, BEFORE ffapp.cpp tests the intra-node NVLink shortcut, so a log produced
with that shortcut ENABLED lists flows that never touched a wire. Those are
counted here as same_node/intra_adj/intra_far bytes, inflating the intra share by
up to 2x (50% of flows were eligible at EP=16, 12.5% at EP=64). Check the run
log's "Intra-node NVLink shortcut:" banner: if it says ENABLED, or the log
predates e2fc399 and has no banner at all, the intra columns are upper bounds and
the intra/inter split at the bottom is not trustworthy. With the shortcut
DISABLED every listed flow is real and the decomposition is exact.

Usage:
  python3 scripts/decompose_flows.py --log <run.log> [--fct <fct_util_out.txt>]
                                     [--panel 16] [--pcols 4] [--csv out.csv]
"""
import argparse
import os
import re
import statistics as st

FLOW_RE = re.compile(r"flow_size:\s*(\d+)\s+src_node:\s*(\d+)\s+dst_node:\s*(\d+)")
FCT_RE = re.compile(r"^FCT\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.eE+-]+)")


def classify(s, d, panel, pcols):
    if s == d:
        return "same_node"
    if s // panel != d // panel:
        return "inter"
    ls, ld = s % panel, d % panel
    rs, cs = ls // pcols, ls % pcols
    rd, cd = ld // pcols, ld % pcols
    if rs == rd:
        return "intra_adj" if abs(cs - cd) == 1 else "intra_far"
    if cs == cd:
        return "intra_adj" if abs(rs - rd) == 1 else "intra_far"
    return "intra_far"          # needs a 2-hop relay, both legs are waveguide


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--fct", default=None, help="logdir/fct_util_out.txt")
    ap.add_argument("--panel", type=int, default=16)
    ap.add_argument("--pcols", type=int, default=4)
    ap.add_argument("--csv", default=None)
    a = ap.parse_args()

    classes = ["same_node", "intra_adj", "intra_far", "inter"]
    bytes_by = {c: 0 for c in classes}
    count_by = {c: 0 for c in classes}
    fcts_by = {c: [] for c in classes}

    with open(a.log, errors="ignore") as fh:
        for line in fh:
            m = FLOW_RE.search(line)
            if m:
                b, s, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
                c = classify(s, d, a.panel, a.pcols)
                bytes_by[c] += b
                count_by[c] += 1

    if a.fct and os.path.exists(a.fct):
        with open(a.fct, errors="ignore") as fh:
            for line in fh:
                m = FCT_RE.match(line)
                if m:
                    s, d, _, f = int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4))
                    fcts_by[classify(s, d, a.panel, a.pcols)].append(f)

    tot_b = sum(bytes_by.values()) or 1
    print(f"panel={a.panel} grid={a.panel//a.pcols}x{a.pcols}   log={os.path.basename(a.log)}")
    print(f"{'class':<11}{'flows':>8}{'bytes':>15}{'share':>8}"
          f"{'fct_mean':>11}{'fct_p99':>11}{'fct_max':>11}")
    rows = []
    for c in classes:
        f = fcts_by[c]
        mean = f"{st.mean(f):.6f}" if f else "-"
        p99 = f"{sorted(f)[int(len(f)*0.99)]:.6f}" if f else "-"
        mx = f"{max(f):.6f}" if f else "-"
        print(f"{c:<11}{count_by[c]:>8}{bytes_by[c]:>15}"
              f"{100*bytes_by[c]/tot_b:>7.1f}%{mean:>11}{p99:>11}{mx:>11}")
        rows.append((c, count_by[c], bytes_by[c], 100*bytes_by[c]/tot_b, mean, p99, mx))

    wire = tot_b - bytes_by["same_node"]
    if wire:
        print(f"\non-wire bytes: {wire}  "
              f"intra {100*(bytes_by['intra_adj']+bytes_by['intra_far'])/wire:.1f}%  "
              f"inter {100*bytes_by['inter']/wire:.1f}%")

    if a.csv:
        import csv as _csv
        with open(a.csv, "w", newline="") as fh:
            w = _csv.writer(fh)
            w.writerow(["class", "flows", "bytes", "byte_share_pct",
                        "fct_mean", "fct_p99", "fct_max"])
            w.writerows(rows)
        print(f"wrote {a.csv}")


if __name__ == "__main__":
    main()
