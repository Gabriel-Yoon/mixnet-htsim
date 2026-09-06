#!/usr/bin/env python3
"""Cross-domain tier power for the EP=32 training cliff, per GPU.

WHY THIS EXISTS. I described glass as carrying "16x the cross-domain bandwidth
(1600 vs 100 GB/s)". That compared glass's PER-EDGE figure against dom64's
PER-GPU figure -- the same units mismatch this project has now catalogued six
times. The correct per-GPU ratio is 4x, not 16x, and the power conclusion turns
on getting it right.

METHOD. The paper's own: per-link bandwidth x pJ/bit of that link class, summed
over the cross-domain tier only, then divided by the GPUs that tier serves. All
bandwidths are per-direction (docs/interconnect_parameters.md section 4b). pJ/bit
figures are taken unchanged from the existing tables -- no new sources.
"""

PJ_GLASS = 1.15          # blended, all links, per-GPU aggregate (main.tex tab:power)
PJ_SCALEOUT = (16, 20)   # scale-out class, total incl. retimers (HotI'25 Tab. I; SLDF)


def watts(gbytes_per_s, pj_per_bit):
    return gbytes_per_s * 1e9 * 8 * pj_per_bit * 1e-12


print("EP=32 training cliff, cross-domain tier only, per direction\n")

# --- glass-FB -------------------------------------------------------------
# 256 nodes / 16 per panel = 16 panels in a 4x4 mesh -> 4 edges per panel,
# 1600 GB/s per edge (GLASS_INTER_BW), G=4 gateways sharing it.
PANEL_GPUS, EDGES, EDGE_BW = 16, 4, 1600
g_panel_bw = EDGES * EDGE_BW
g_per_gpu_bw = g_panel_bw / PANEL_GPUS
g_panel_w = watts(g_panel_bw, PJ_GLASS)
g_per_gpu_w = g_panel_w / PANEL_GPUS

print(f"glass-FB   panel = {PANEL_GPUS} GPUs, {EDGES} edges x {EDGE_BW} GB/s")
print(f"           tier bandwidth  {g_panel_bw:>6.0f} GB/s/panel = {g_per_gpu_bw:>6.1f} GB/s/GPU")
print(f"           tier power      {g_panel_w:>6.1f} W/panel    = {g_per_gpu_w:>6.2f} W/GPU"
      f"   @ {PJ_GLASS} pJ/bit")

# --- NVL5 dom64 -----------------------------------------------------------
DOM_GPUS, NIC_BW = 64, 100          # 800G Ethernet per GPU (MixNet S8)
d_dom_bw = DOM_GPUS * NIC_BW
print(f"\nnvl5_dom64 domain = {DOM_GPUS} GPUs, {NIC_BW} GB/s scale-out NIC per GPU")
print(f"           tier bandwidth  {d_dom_bw:>6.0f} GB/s/domain = {NIC_BW:>6.1f} GB/s/GPU")
for pj in PJ_SCALEOUT:
    d_dom_w = watts(d_dom_bw, pj)
    print(f"           tier power      {d_dom_w:>6.1f} W/domain   = {d_dom_w/DOM_GPUS:>6.2f} W/GPU"
          f"   @ {pj} pJ/bit")

# --- the comparison -------------------------------------------------------
print("\n--- per GPU ---")
print(f"bandwidth ratio  glass / dom64 = {g_per_gpu_bw/NIC_BW:.1f}x"
      f"   (NOT 16x -- that compared per-edge against per-GPU)")
for pj in PJ_SCALEOUT:
    d_w = watts(DOM_GPUS * NIC_BW, pj) / DOM_GPUS
    print(f"power ratio      glass / dom64 = {g_per_gpu_w/d_w:.2f}x        @ {pj} pJ/bit"
          f"   -> glass uses {d_w/g_per_gpu_w:.1f}x LESS")
print("\n--- GB/s per watt, the axis the paper actually claims ---")
for pj in PJ_SCALEOUT:
    d_w = watts(DOM_GPUS * NIC_BW, pj) / DOM_GPUS
    print(f"  glass {g_per_gpu_bw/g_per_gpu_w:8.1f}   dom64 {NIC_BW/d_w:6.1f}"
          f"   = {(g_per_gpu_bw/g_per_gpu_w)/(NIC_BW/d_w):5.1f}x better   @ {pj} pJ/bit")

print("""
READING. Glass delivers 4x the cross-domain bandwidth per GPU while drawing
3.5-4.3x LESS power in that tier, so the measured 3.71x makespan win at EP=32 is
not bought with a power budget the baseline does not have -- it survives
iso-power normalisation with room to spare, and the honest headline is the
GB/s/W ratio rather than the raw speedup.

CAVEAT. This is the cross-domain tier ONLY, which is the tier that decides this
result. It is not a whole-system power comparison: glass's intra-panel tier and
dom64's in-domain NVLink fabric are both excluded, as is switch power on both
sides. State that scope wherever the ratio appears.""")
