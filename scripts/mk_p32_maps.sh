#!/bin/bash
# Port maps for a 32-GPU panel, generated FROM THE TRAFFIC and then verified.
#
# The EP=128 8x8 map was generated with used_pairs=None: it laid down a generic
# ep/dp/pp pattern, cabled 28 of the 36 panel pairs the workload uses, and every
# run on it came back status=blocked. gen_port_map.py has a --used-pairs option
# that takes the pairs the workload actually touches; it was not used. It is used
# here, and the result is then checked with portmap_coverage.py, which is the
# check that turns "should cover" into "does cover".
#
# The used-pairs ground truth comes from the committed hop logs, divided into
# 32-GPU panels. Those logs are workload-determined and topology-independent -- the
# same (src,dst) multiset whichever fabric is loaded -- so re-panelling them by 32
# is exactly the set of cross-panel pairs a 32-GPU panel would see.
set -uo pipefail
R=/storage/scratch1/8/syoon351/repos/panel_scale_glass_flattened_butterfly
cd "$R"
mkdir -p /tmp/p32_$$

for spec in "16 128 4" "32 256 8" "64 512 16"; do
  set -- $spec; ep=$1 nodes=$2 npanel=$3
  UP=/tmp/p32_$$/used_ep${ep}.txt
  python3 - "$ep" "$UP" <<'PY'
import sys, collections
ep, out = sys.argv[1], sys.argv[2]
c = collections.Counter()
for L in open("src/clos/datacenter/tier_logs/tier_ep%s.hoplog" % ep):
    f = L.split()
    if len(f) >= 3 and f[1].lstrip("-").isdigit():
        a, b = int(f[1]) // 32, int(f[2]) // 32
        if a != b:
            c[(min(a, b), max(a, b))] += 1
with open(out, "w") as fh:
    for (a, b), n in sorted(c.items()):
        fh.write("%d %d %d\n" % (a, b, n))
print("  EP=%s: %d cross-panel pairs at psize=32" % (ep, len(c)))
PY
  OUT=$R/experiments/portmaps/p32_ep${ep}.txt
  python3 scripts/gen_port_map.py --dp 2 --tp 1 --pp 4 --ep "$ep" --psize 32 \
      --used-pairs "$UP" -o "$OUT" > /dev/null
  echo "  wrote $(basename "$OUT")  ($(grep -vc '^#' "$OUT") cabled pair lines)"
  python3 scripts/portmap_coverage.py "$OUT" "src/clos/datacenter/tier_logs/tier_ep${ep}.hoplog" 32 \
    || { echo "REFUSING: generated map still does not cover EP=$ep" >&2; exit 1; }
done
rm -rf /tmp/p32_$$
echo
echo "all three 32-GPU-panel maps generated and verified"
