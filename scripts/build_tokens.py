#!/usr/bin/env python3
"""Tokens per training iteration for the quoted task graphs -- where it is recorded.

WHAT IS RECORDED AND WHAT IS NOT. Each graph ships a .meta whose `config` block
carries dp, tp, pp, ep, topk, layers, seq, mb and devices. It does NOT carry the
global batch size, and tokens per iteration is batch x seq. So the config alone
cannot give the token count.

The formula suggested for this table -- DP x microbatch count x per-microbatch batch
x sequence length -- needs a per-microbatch batch size that is recorded nowhere, and
`mb` in the filename is FlexFlow's --microbatchsize, which is how the global batch is
split rather than how large it is (README: "-b or --batch-size: global batch size in
each iteration"). Multiplying by mb would count the same tokens mb times.

Where a generator log survives, it says the batch size directly:

    attention batch size:128 ... layer norm effective_batch_size:4096,
    effective_num_elements:131072

and 128 x 1024 = 131072 exactly, so effective_num_elements is batch x seq -- the
token count -- and the two independent numbers in that line agree. The check below
requires that agreement before it will fill a row: a log whose batch x seq does not
equal its element count is reported, not used.

Only ONE of the four quoted graphs has such a log (llamaMoE EP=32). The rest are
left blank with the reason in the row, because a per-token figure computed from an
assumed batch size would be an assumption presented as an absolute.
"""
import csv, glob, json, os, re

RES = "/storage/scratch1/8/syoon351/repos/mixnet-sim/mixnet-flexflow/results"
OUT = ("/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly"
       "/experiments/results/paper/tokens_per_iter.csv")

# the graphs the paper quotes, plus the EP=16 microbatch sweep
WANTED = ["llamaMoE_paper_dp2tp1pp4_ep16top2_L4_seq1024_mb%d_H100" % m for m in (4, 8, 16, 32)] + [
    "llamaMoE_paper_dp2tp1pp4_ep32top2_L4_seq1024_mb8_H100",
    "qwenMoE_paper_dp2tp1pp4_ep64top4_L4_seq1024_mb8_H100",
    "arctic_paper_dp2tp1pp4_ep128top2_L4_seq1024_mb8_H100",
]

RE_BATCH = re.compile(r"attention batch size:(\d+)")
RE_ELEMS = re.compile(r"effective_num_elements:(\d+)")


def from_log(stem, seq):
    """(tokens, batch, logfile) from a generator log, or (None, None, reason)."""
    logs = sorted(glob.glob(os.path.join(RES, stem + "*.log")))
    if not logs:
        return None, None, "no generator log for this graph"
    for lg in logs:
        batch = elems = None
        with open(lg, errors="replace") as fh:
            for line in fh:
                if batch is None:
                    m = RE_BATCH.search(line)
                    if m:
                        batch = int(m.group(1))
                if elems is None:
                    m = RE_ELEMS.search(line)
                    if m:
                        elems = int(m.group(1))
                if batch is not None and elems is not None:
                    break
        if batch is None or elems is None:
            continue
        # the two numbers in that line are independent; they must agree
        if batch * seq != elems:
            return None, None, ("REFUSED %s: attention batch %d x seq %d = %d but "
                                "effective_num_elements is %d"
                                % (os.path.basename(lg), batch, seq, batch * seq, elems))
        return elems, batch, os.path.basename(lg)
    return None, None, "generator log present but carries no batch/element line"


rows = []
for stem in WANTED:
    meta = os.path.join(RES, stem + ".meta")
    if not os.path.exists(meta):
        print("skip %s: no .meta" % stem); continue
    cfg = json.load(open(meta)).get("config", {})
    seq = int(cfg.get("seq", 0))
    tokens, batch, src = from_log(stem, seq)
    if tokens is None and src.startswith("REFUSED"):
        print("  " + src)
    rows.append(dict(
        graph=stem, model=stem.split("_")[0],
        dp=cfg.get("dp"), tp=cfg.get("tp"), pp=cfg.get("pp"), ep=cfg.get("ep"),
        topk=cfg.get("topk"), layers=cfg.get("layers"), seq=seq, mb=cfg.get("mb"),
        devices=cfg.get("devices"),
        global_batch=(batch if batch is not None else ""),
        tokens_per_iter=(tokens if tokens is not None else ""),
        source=(src if tokens is not None else ""),
        note=("batch x seq from the generator log; the two numbers on that line "
              "agree (%d x %d = %d)" % (batch, seq, tokens) if tokens is not None
              else "NOT DERIVABLE: %s. The .meta config records dp/tp/pp/ep/topk/"
                   "layers/seq/mb/devices but NOT the global batch size, and tokens "
                   "per iteration is batch x seq. mb is --microbatchsize (how the "
                   "global batch is split), not a per-microbatch batch size, so it "
                   "must not be multiplied in." % src)))

with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)

have = sum(1 for r in rows if r["tokens_per_iter"] != "")
print("wrote %s: %d graph(s), %d with a sourced token count" % (OUT, len(rows), have))
for r in rows:
    print("  %-58s ep=%-4s mb=%-3s tokens=%s"
          % (r["graph"][:58], r["ep"], r["mb"], r["tokens_per_iter"] or "-"))
