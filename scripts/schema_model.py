#!/usr/bin/env python3
"""Split cliff.csv's `model` into model (family) and model_name (workload).

cliff_pkt.csv already uses `model`=pkt with `model_name`=llamaMoE, while
cliff.csv used `model`=llamaMoE and had no model_name -- the same column name
meaning two different things in two files that get plotted together. (The same
collision produced the EP=64 mismatch: island_cliff.sh and pkt_cliff.sh both
call their fbuf variable Q64 and point it at different models.)

After this, in every cliff CSV:
    model       family: island | pkt | glass
    model_name  workload: llamaMoE | qwenMoE | qwen2_57b | arctic | dbrx

Two parts, deliberately separable:

  --plot   patch scripts/figures/plot_paper.py to read model_name with a
           fallback to model. Safe at any time, and safe to run first: the
           fallback means the figures are correct before AND after migration.

  --csv F  migrate a CSV. NOT safe while a job is appending to it -- a row
           written against the old header lands in the wrong columns. Run it
           only once the writer has exited.
"""
import csv, os, sys

ROOT = "/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
PLOT = os.path.join(ROOT, "scripts/figures/plot_paper.py")

FAMILY_BY_SYSTEM = {
    "nvl64": "island", "hgx8": "island",
    "nvl64_pkt": "pkt", "hgx8_pkt": "pkt",
    "glassfb": "glass",
}


def patch_plot():
    s = open(PLOT).read()
    if "def mname(" in s:
        print("plot_paper.py already patched")
        return
    helper = (
        'def mname(r):\n'
        '    """Workload name. cliff.csv used to call this `model`; that column now\n'
        '    carries the family (island|pkt|glass), matching cliff_pkt.csv. The\n'
        '    fallback keeps un-migrated CSVs plotting correctly."""\n'
        '    return r.get("model_name") or r.get("model")\n'
        '\n'
        'def f(name):\n'
    )
    anchor = "def f(name):\n"
    assert s.count(anchor) == 1, "f() anchor"

    # Replace the call sites BEFORE inserting the helper, or the global replace
    # rewrites the helper's own body into `return r.get("model_name") or mname(r)`
    # -- infinite recursion.
    n = s.count('r.get("model")')
    s = s.replace('r.get("model")', 'mname(r)')
    s = s.replace(anchor, helper, 1)
    open(PLOT, "w").write(s)
    print("plot_paper.py patched (%d call sites -> mname())" % n)


def migrate(path):
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        print("%-28s empty, skipped" % os.path.basename(path))
        return
    fields = list(rows[0].keys())
    if "model_name" in fields:
        print("%-28s already has model_name" % os.path.basename(path))
        return
    if "model" not in fields or "system" not in fields:
        print("%-28s no model/system column, skipped" % os.path.basename(path))
        return

    fields.insert(fields.index("model") + 1, "model_name")
    unknown = set()
    for r in rows:
        r["model_name"] = r["model"]
        fam = FAMILY_BY_SYSTEM.get(r.get("system", ""))
        if fam is None:
            unknown.add(r.get("system", ""))
            fam = r["model"]          # leave it rather than invent a family
        r["model"] = fam
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    print("%-28s migrated (%d rows)%s" % (os.path.basename(path), len(rows),
          "  UNMAPPED systems: %s" % sorted(unknown) if unknown else ""))


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--plot" in args:
        patch_plot()
    for i, a in enumerate(args):
        if a == "--csv":
            migrate(args[i + 1])
