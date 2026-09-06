#!/usr/bin/env python3
"""D35: classify every FlexFlow task graph by its ATTENTION measurement mode.

The mode is a property of how a graph was generated and no artifact records it,
yet it changes what the compute costs mean. Two graphs on one curve must share it.

SIGNATURE. With FF_FULLMEASURE the attention operator is measured on the GPU and
reports real tensor sizes. With the analytical fallback (NO_FULLMEASURE=1) the
MultiHeadAttention node carries in/out/weight bytes of exactly 0. That zero is
the discriminator, and it is visible in the .txt dot dump beside each .fbuf.

Corroborated for llamaMoE by scripts/log_paper_llamaMoE.txt, which shows the
FF_FULLMEASURE path aborting in attention.cu:35 (cuDNN INTERNAL_ERROR) for the
same TP=1 config -- so the analytical mode was not a choice there, it was forced.

Writes a .meta sidecar next to each graph and prints a per-EP consistency check,
because the thing that actually matters is not any single graph's mode but
whether graphs compared against each other agree.
"""
import glob, json, os, re, sys

RES = "/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results"

# MultiHeadAttention node: ... { in | out | weight | bytes } | { A | B | C } }
ATTN = re.compile(
    r"MultiHeadAttention_\d+.*?\{ in \| out \| weight \| bytes \} \| \{ ([^}]*) \}")
NAME = re.compile(
    r"_dp(\d+)tp(\d+)pp(\d+)_ep(\d+)top(\d+)_L(\d+)_seq(\d+)_mb(\d+)")

rows = []
for fb in sorted(glob.glob(os.path.join(RES, "*.fbuf"))):
    base = fb[:-5]
    txt = base + ".txt"
    name = os.path.basename(base)
    mode, nattn, detail = "UNKNOWN", 0, "no .txt sidecar"
    if os.path.exists(txt):
        with open(txt, errors="ignore") as fh:
            body = fh.read()
        vals = ATTN.findall(body)
        nattn = len(vals)
        if not vals:
            mode, detail = "NO_ATTENTION_NODE", "no MultiHeadAttention in graph"
        else:
            allzero = all(
                all(float(x.strip()) == 0.0 for x in v.split("|"))
                for v in vals)
            anyzero = any(
                all(float(x.strip()) == 0.0 for x in v.split("|"))
                for v in vals)
            if allzero:
                mode, detail = "analytical", "all attention nodes report 0 bytes"
            elif not anyzero:
                mode, detail = "measured", "attention nodes report real tensor bytes"
            else:
                mode, detail = "MIXED", "some attention nodes zero, some not"

    m = NAME.search(name)
    cfg = {}
    if m:
        dp, tp, pp, ep, topk, L, seq, mb = (int(x) for x in m.groups())
        cfg = dict(dp=dp, tp=tp, pp=pp, ep=ep, topk=topk,
                   layers=L, seq=seq, mb=mb, devices=dp * tp * pp * ep)

    meta = dict(graph=name, attention_mode=mode, evidence=detail,
                attention_nodes=nattn, size_bytes=os.path.getsize(fb),
                config=cfg,
                note="attention_mode is inferred from the 0-byte signature, not "
                     "recorded at generation time; see docs/paper_todo.md D35")
    with open(base + ".meta", "w") as fh:
        json.dump(meta, fh, indent=2)
    rows.append((name, mode, cfg.get("ep"), cfg.get("tp"), cfg.get("devices"), nattn))

print(f"{'graph':<66}{'mode':<20}{'EP':>5}{'TP':>4}{'dev':>7}{'attn':>6}")
for name, mode, ep, tp, dev, na in rows:
    print(f"{name:<66}{mode:<20}{str(ep):>5}{str(tp):>4}{str(dev):>7}{na:>6}")

print("\n=== consistency by EP (curve-mates must agree) ===")
by_ep = {}
for name, mode, ep, tp, dev, na in rows:
    if ep is not None:
        by_ep.setdefault(ep, set()).add(mode)
bad = False
for ep in sorted(by_ep):
    modes = by_ep[ep]
    ok = "OK" if len(modes) == 1 else "MISMATCH"
    if len(modes) != 1:
        bad = True
    print(f"  EP={ep:<5} {ok:<10} {sorted(modes)}")

allmodes = {m for _, m, ep, _, _, _ in rows if ep is not None}
print(f"\nAll EP-bearing graphs: {sorted(allmodes)}")
print("MISMATCH FOUND — curves mixing modes are not readable" if bad
      else "Uniform across every graph: curves are internally comparable.")
