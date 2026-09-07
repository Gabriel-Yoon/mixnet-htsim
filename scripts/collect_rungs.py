#!/usr/bin/env python3
"""Merge the per-rung CSVs and apply the vanishing-timeout rule across them.

Every rung ran as its own job and wrote its own file, so the walk that is normally
sequential is reconstructed here. THE RULE IS UNCHANGED: a walk's quoted row is
its first rung, by buffer, with no timeouts. Running the rungs simultaneously
changes the order of discovery, not the criterion.

What this refuses to do:

- quote a rung whose job has not finished. A file with a sentinel and no data row
  is a job still running or one that died; either way it is not a zero-timeout
  result, and treating a missing rung as absent-therefore-fine would let a walk
  be quoted at a buffer larger than its true vanishing point.
- quote a walk with a GAP below the candidate. If 8x has no timeouts but 4x has
  not reported, the first zero-timeout rung might be 4x. The walk is reported as
  incomplete rather than quoted at 8x.
- quote a row without link_rate_fixed=yes. That is gate_quotable's job too, but
  saying it here means a stale row cannot reach a table in the first place.
"""
import collections, csv, glob, os, re, sys

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
RUNGS = os.path.join(ROOT, "experiments/results/paper/rungs")
OUT = os.path.join(ROOT, "experiments/results/paper/cliff_postfix.csv")


def num(v, d=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d



# Which rungs were SUBMITTED for a walk, from the files on disk. csv_open creates
# the file when the job starts, so a rung that is merely unfinished still has one;
# that is what distinguishes "still running" from "never submitted", and the
# completed rows alone cannot say which.
_TAG_Q = re.compile(r"_q(\d+)\.csv$")


# The ladder each walk was submitted with. These are constants shared with
# submit_all_rungs.sh; deriving them from the files on disk cannot tell a job that
# was never submitted from one that has not STARTED, and a walk missing its lowest
# rung would then look complete.
LADDERS = {
    ("glassfb", "128"): [533, 1066, 2133, 4267, 8533, 17067],
    ("glassfb", "64"):  [533, 1064, 2133, 4267, 8533, 17067],
    ("glassfb", "32"):  [266, 533, 1066, 2133, 4267, 8533],
    ("glassfb", "16"):  [133, 266, 532, 1064, 2128, 4256],
    ("hgx8_pkt", "16"): [306, 612, 1224, 2448, 4896, 9792],
    ("hgx8_pkt", "32"): [306, 612, 1224, 2448, 4896, 9792],
    ("hgx8_pkt", "64"): [306, 612, 1224, 2448, 4896, 9792],
    ("nvl64_pkt_s1", "16"): [600, 1200, 2400, 4800, 9600, 19200],
    ("nvl64_pkt_s1", "32"): [600, 1200, 2400, 4800, 9600, 19200],
    ("nvl64_pkt_s1", "64"): [600, 1200, 2400, 4800, 9600, 19200],
}


def submitted_q(key):
    sysname, ep, mb, _cab = key
    known = LADDERS.get((sysname, str(ep)))
    if known:
        return {float(q) for q in known}
    # Fallback: the files on disk. Weaker, because a queued-but-unstarted job has
    # no file and will not appear here.
    if sysname == "glassfb":
        pre = "g%s" % ep if not mb else "g%sm%s" % (ep, mb)
    elif sysname == "hgx8_pkt":
        pre = "h%s" % ep
    elif sysname == "nvl64_pkt_s1":
        pre = "s1_%s" % ep
    else:
        return set()
    out = set()
    for f in glob.glob(os.path.join(RUNGS, pre + "_q*.csv")):
        m = _TAG_Q.search(os.path.basename(f))
        if m:
            out.add(float(m.group(1)))
    print("  note: %s ep=%s has no declared ladder; completeness inferred from disk"
          % (sysname, ep), file=sys.stderr)
    return out

rows, pending, unfixed, contaminated = [], 0, 0, []
for p in sorted(glob.glob(os.path.join(RUNGS, "*.csv"))):
    if os.path.exists(p + ".writing"):
        pending += 1
        continue                                  # job still holding it
    try:
        rs = list(csv.DictReader(open(p, newline="")))
    except OSError:
        continue
    # One job, one file. If a rung file holds more than one completed row, two
    # jobs wrote it -- which happened today: submit_all_rungs.sh was run twice
    # (once as a guard test that was expected to refuse and did not), so both
    # copies of a rung targeted the same tag. csv_open truncates while the twin
    # appends. The rows may still be individually correct, but the file can no
    # longer say which job produced which, so it is refused rather than guessed.
    done_rows = [x for x in rs if (x.get("status") or "").strip() not in
                 ("submitted", "ABORTED", "")]
    if len(done_rows) > 1:
        print("  REFUSED %s: %d completed rows in one rung file -- two jobs wrote it"
              % (os.path.basename(p), len(done_rows)), file=sys.stderr)
        contaminated.append(os.path.basename(p))
        continue

    for r in rs:
        st = (r.get("status") or "").strip()
        if st in ("submitted", "ABORTED", ""):
            pending += 1
            continue
        if num(r.get("makespan_ms")) in (None, 0.0):
            pending += 1
            continue
        if (r.get("link_rate_fixed") or "").strip().lower() != "yes":
            unfixed += 1
            continue
        r["_src"] = os.path.basename(p)
        rows.append(r)

print("%d completed rung(s); %d still pending or without a makespan; %d without the fix flag"
      % (len(rows), pending, unfixed))
if contaminated:
    print("  %d rung file(s) refused as double-written: %s"
          % (len(contaminated), ", ".join(contaminated[:6])), file=sys.stderr)
if unfixed:
    print("  WARNING: %d row(s) came from a binary that does not assert the link-rate fix "
          "-- excluded" % unfixed, file=sys.stderr)

# group into walks: one walk per (system, ep, mb, cabling)
walks = collections.defaultdict(list)
for r in rows:
    key = (r.get("system", ""), r.get("ep", ""), (r.get("mb") or "").strip(),
           (r.get("cabling") or "").strip())
    walks[key].append(r)

quoted = 0
for key, g in sorted(walks.items()):
    g.sort(key=lambda r: num(r.get("q") or r.get("q_nvs"), 0.0))
    ok = [r for r in g if (r.get("status") or "") == "sweep"
          and num(r.get("relayed_pairs"), 0) == 0]
    zero = [r for r in ok if num(r.get("rtos"), -1) == 0]
    branch = "first zero-timeout rung (post-fix binary)"
    if not zero:
        # drop-aware branch: timeouts that come with no measured loss are not
        # congestion and do not respond to buffer. A rung with timeouts and no
        # drop COUNT is not eligible -- absence of a count is not evidence of
        # no loss.
        zero = [r for r in ok
                if str(r.get("drops", "")).strip().isdigit()
                and int(str(r.get("drops")).strip()) == 0
                and num(r.get("rtos"), 0) > 0]
        if zero:
            branch = ("first rung with zero measured drops; %g spurious timeouts "
                      "(buffer-invariant, validated counter)"
                      % num(zero[0].get("rtos"), 0))
    for r in g:
        r["quotable"] = "no"
        r["quotable_why"] = "not the first qualifying rung of this walk"
        # An explicit marker for the gate to defer on. Deciding precedence from
        # the wording of quotable_why coupled behaviour to prose and silently
        # dropped the drop-aware branch.
        r["quoted_by"] = "collector"
    if zero:
        first = zero[0]
        fq = num(first.get("q") or first.get("q_nvs"), 0.0)
        # every rung below the candidate must have reported, or the true first
        # zero-timeout rung may simply not be in yet
        have_below = {num(r.get("q") or r.get("q_nvs"), 0.0) for r in g
                      if num(r.get("q") or r.get("q_nvs"), 0.0) < fq}
        want_below = {q for q in submitted_q(key) if q < fq}
        missing = sorted(want_below - have_below)
        if not missing:
            first["quotable"] = "yes"
            first["quotable_why"] = branch
            quoted += 1
            _d = str(first.get("drops", "")).strip()
            print("  QUOTED  %-12s ep=%-4s mb=%-3s q=%-7s %10s ms  rtos=%-7s drops=%-9s "
                  "(%d rungs in) [%s]"
                  % (key[0], key[1], key[2] or "-", first.get("q") or first.get("q_nvs"),
                     first.get("makespan_ms"), first.get("rtos"),
                     _d if _d else "not measured", len(g),
                     "timeout-free" if num(first.get("rtos"), 0) == 0 else "zero measured loss"))
        else:
            print("  gap     %-12s ep=%-4s mb=%-3s zero-timeout at q=%s but %d rung(s) "
                  "below have not reported (%s) -- not quoted yet"
                  % (key[0], key[1], key[2] or "-", fq, len(missing),
                     ", ".join("%g" % m for m in missing)))
    else:
        nodrops = sum(1 for r in g if not str(r.get("drops", "")).strip().isdigit())
        print("  no zero %-12s ep=%-4s mb=%-3s %d rung(s); none timeout-free and none "
              "with a measured zero-drop count (%d rung(s) have no drop count at all)"
              % (key[0], key[1], key[2] or "-", len(g), nodrops))

if rows:
    fields = []
    for r in rows:
        for k in r:
            if k not in fields and k != "_src":
                fields.append(k)
    fields.append("source")
    with open(OUT, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            r["source"] = r.pop("_src", "")
            w.writerow(r)
    print("\nwrote %s: %d rung(s), %d walk(s) quoted" % (OUT, len(rows), quoted))
