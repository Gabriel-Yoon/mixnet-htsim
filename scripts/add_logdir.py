#!/usr/bin/env python3
"""Give every simulator invocation its own output directory.

The binary defaults to ./logs/<exe>_<%m-%d-%H-%M-%S>, a one-second name. Two
cells of different jobs that start in the same second share it and append to one
fct_util_out.txt, splicing each other's lines. It already happened once, between
a qfine cell and the EP=64 cliff cell.

The binary accepts -logdir, so the path becomes an identity rather than a clock
reading: script name, job id, PID, and a per-invocation counter. Two runs cannot
collide even inside the same job, the same second, or the same node.

Only scripts whose jobs have exited are patched: this inserts text, shifting
every later byte offset in a file bash may still be reading.
"""
import os, re, sys

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
TARGETS = sys.argv[1:]
assert TARGETS, "pass the scripts to patch (only ones whose jobs have exited)"

PREAMBLE = (
    "# Unique output directory per invocation. The binary's default is a\n"
    "# one-second timestamp, which two concurrent cells can share; see\n"
    "# scripts/logdir_collisions.py and methods_provenance.md sub-class I.\n"
    "_LOGDIR_N=0\n"
    "_logdir() { _LOGDIR_N=$((_LOGDIR_N + 1)); "
    "printf './logs/%s_%s_%s_%s' \"$(basename \"$0\" .sh)\" \"${SLURM_JOB_ID:-local}\" \"$$\" \"$_LOGDIR_N\"; }\n"
)

RE_CALL = re.compile(r"(\$BIN|\./htsim_tcp_[a-z0-9_]+)(\s+-nodes)")

for name in TARGETS:
    p = os.path.join(ROOT, "scripts", name)
    if not os.path.exists(p):
        print("%-26s MISSING" % name); continue
    s = open(p).read()
    if "_logdir()" in s:
        print("%-26s already has -logdir" % name); continue
    n = len(RE_CALL.findall(s))
    if n == 0:
        print("%-26s SKIPPED: no `<binary> -nodes` invocation found" % name); continue
    s = RE_CALL.sub(lambda m: '%s -logdir "$(_logdir)"%s' % (m.group(1), m.group(2)), s)
    anchor = "set -uo pipefail\n"
    if s.count(anchor) != 1:
        print("%-26s SKIPPED: no unique `set -uo pipefail`" % name); continue
    s = s.replace(anchor, anchor + PREAMBLE, 1)
    open(p, "w").write(s)
    print("%-26s %d invocation(s) given their own -logdir" % (name, n))
