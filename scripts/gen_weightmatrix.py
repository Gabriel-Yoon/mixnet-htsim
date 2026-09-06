#!/usr/bin/env python3
"""Generate an ep x ep expert-to-expert token weight matrix for MixNet (htsim).
Each ROW sums to 32768 (the htsim convention; ffapp asserts total_row_number==32768).
Models realistic MoE a2a skew: a few hot experts get many tokens, a long tail gets few.
Requires the ffapp.cpp `%8 -> %weight_matrix.size()` patch so ep != 8 is honored.

  python gen_weightmatrix.py 16 > test/num_global_tokens_per_expert_ep16.txt
  python gen_weightmatrix.py 64 --skew 2.0 > .../ep64.txt
Output format (one line):  [[a,b,...],[c,d,...],...]
"""
import sys, random, argparse
TOTAL = 32768

ap = argparse.ArgumentParser()
ap.add_argument("ep", type=int, help="number of experts (matrix is ep x ep)")
ap.add_argument("--skew", type=float, default=1.6, help="zipf-like exponent; higher = more skewed")
ap.add_argument("--seed", type=int, default=0)
a = ap.parse_args()
random.seed(a.seed)

def skewed_row(n, skew):
    # zipf-ish weights with a random hot-expert permutation, then quantize to sum=TOTAL
    base = [1.0 / ((i + 1) ** skew) for i in range(n)]
    random.shuffle(base)
    s = sum(base)
    vals = [int(round(TOTAL * b / s)) for b in base]
    # fix rounding so the row sums to exactly TOTAL
    diff = TOTAL - sum(vals)
    vals[max(range(n), key=lambda i: vals[i])] += diff
    # guarantee non-negative
    return [max(0, v) for v in vals]

rows = [skewed_row(a.ep, a.skew) for _ in range(a.ep)]
# sanity
for r in rows:
    assert sum(r) == TOTAL, sum(r)
print("[" + ",".join("[" + ",".join(str(v) for v in r) + "]" for r in rows) + "]")
