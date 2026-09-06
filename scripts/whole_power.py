#!/usr/bin/env python3
"""Whole-interconnect iso-power for the training cliff, EP=32, per GPU.

The tier-only comparison (scripts/tier_power.py) is the right lens for WHY glass
wins, but the paper's established iso-power basis (Fig 6a, C26) normalises the
whole interconnect, so the training result has to be reportable in that frame too.

THE HONEST FINDING, up front: it is NOT determinable from our current sources.
The answer hinges entirely on NVLink's pJ/bit, which docs/interconnect_parameters.md
does not carry. The nearest thing it has is "[O] Scale-up class (parity threshold)
< 5 pJ/bit", which is a CLASS BOUND, not a measurement of NVLink. Across the
plausible range the comparison flips sign, so picking a value would be choosing
the conclusion.

Link counts for a 4x4 FB panel, derived rather than assumed:
  electrical adjacent : 4 rows x 3 + 4 cols x 3 = 24 links
  optical far         : per row, C(4,2)=6 pairs - 3 adjacent = 3 far; x4 rows = 12,
                        same for columns = 12; total 24 links
  inter-panel         : 4 mesh edges
"""

PJ_GLASS = 1.15
PJ_SCALEOUT = 16          # scale-out class, total incl. retimers (HotI'25 Tab. I)
PJ_NVLINK_RANGE = (1.0, 2.0, 5.0)   # 5.0 = the doc's scale-up CLASS bound, not NVLink itself

def w(gbs, pj):
    return gbs * 1e9 * 8 * pj * 1e-12

# --- glass-FB, EP=32 configuration ---------------------------------------
ELEC_BW, OPT_BW, EDGE_BW = 1800, 384, 1600
N_ELEC, N_OPT, N_EDGE, PANEL = 24, 24, 4, 16

panel_bw = N_ELEC * ELEC_BW + N_OPT * OPT_BW + N_EDGE * EDGE_BW
g_bw = panel_bw / PANEL
g_w = w(panel_bw, PJ_GLASS) / PANEL

print("glass-FB, whole interconnect, per GPU")
print(f"  electrical {N_ELEC} x {ELEC_BW} = {N_ELEC*ELEC_BW:>6} GB/s")
print(f"  optical    {N_OPT} x {OPT_BW:>4} = {N_OPT*OPT_BW:>6} GB/s")
print(f"  inter      {N_EDGE} x {EDGE_BW} = {N_EDGE*EDGE_BW:>6} GB/s")
print(f"  panel total {panel_bw} GB/s over {PANEL} GPUs = {g_bw:.0f} GB/s/GPU")
print(f"  power @ {PJ_GLASS} pJ/bit = {g_w:.1f} W/GPU\n")

# --- nvl5_dom64 -----------------------------------------------------------
NVL_BW, NIC_BW = 900, 100
nic_w = w(NIC_BW, PJ_SCALEOUT)
print(f"nvl5_dom64, whole interconnect, per GPU")
print(f"  in-domain NVLink5 {NVL_BW} GB/s, scale-out NIC {NIC_BW} GB/s"
      f" = {NVL_BW+NIC_BW} GB/s/GPU")
print(f"  NIC power @ {PJ_SCALEOUT} pJ/bit = {nic_w:.1f} W/GPU")
print(f"  NVLink power depends on a figure we do not have:\n")

print(f"  {'NVLink pJ/bit':>14} {'NVLink W':>10} {'total W':>9} {'glass/dom64':>13}  verdict")
for pj in PJ_NVLINK_RANGE:
    nv_w = w(NVL_BW, pj)
    tot = nv_w + nic_w
    r = g_w / tot
    verdict = ("glass LOWER power - 3.71x survives outright" if r < 1
               else f"glass {r:.2f}x HIGHER - speedup must be normalised")
    print(f"  {pj:>14.1f} {nv_w:>10.1f} {tot:>9.1f} {r:>13.2f}  {verdict}")

print(f"""
READING. The sign of the whole-interconnect comparison is set by NVLink's pJ/bit,
and our sources do not contain it. At the doc's scale-up class bound (5 pJ/bit)
glass draws less power than dom64 and the 3.71x stands unnormalised; at 1 pJ/bit
glass draws {g_w / (w(NVL_BW,1.0)+nic_w):.2f}x more and the speedup would have to be normalised down.

So "survives iso-power with room to spare" is SAFE at the cross-domain tier, where
both figures are sourced, and NOT YET ESTABLISHED whole-interconnect. Two ways
forward, in order of preference:
  1. Source an NVLink pJ/bit figure and compute it properly.
  2. Report the tier comparison as the primary, state the whole-interconnect
     result as a function of NVLink pJ/bit with this table, and let the reader
     see the dependence instead of hiding it behind a chosen value.

Note the structural asymmetry either way: glass spends most of its interconnect
power on the INTRA-panel tier ({(N_ELEC*ELEC_BW + N_OPT*OPT_BW)/panel_bw*100:.0f}% of its
bandwidth), which is not the tier that decides this result. A whole-interconnect
normalisation therefore charges glass for capability the workload did not use --
which is an argument for reporting both, not for reporting only the flattering one.""")
