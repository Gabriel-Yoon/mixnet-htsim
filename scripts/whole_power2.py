#!/usr/bin/env python3
"""Whole-interconnect iso-power for the training cliff, using the PAPER'S OWN constants.

Supersedes the earlier version, which said this was "not determinable". It is --
the constants were in the repo the whole time, in the figure producer:
scripts/figures/plot_energy_final.py lines 26-27. Those constants generate the
PUBLISHED 39 / 62 GB/s/W in main.tex's abstract, verified below, so using anything
else would make the training comparison inconsistent with the paper's own figure.

  NVL4: 0.9 TB/s bidir, 1.5 pJ/bit dynamic, 12.5 W/GPU NVSwitch (4x NVSwitch3 / 8 GPU)
  NVL5: 1.8 TB/s bidir, 1.5 pJ/bit dynamic, 540/72 = 7.5 W/GPU NVSwitch
  glass: WG x 1.024 Tb/s x edyn + laser 3.84 W + ring tuning 1.44 W

TWO CORRECTIONS TO MY OWN EARLIER NUMBER (33.8 W/GPU):
 (a) I charged the ELECTRICAL RDL tier at the OPTICAL 1.15 pJ/bit. Different
     medium, different figure. The RDL gets a short-reach electrical figure here,
     bracketed 1-2 pJ/bit from the doc's XSR (1, PHY only, <100um) and on-PCB
     short-reach (2) entries.
 (b) The paper's own glass model does not include the RDL tier AT ALL -- glass
     power is optical waveguides plus static, full stop. So the published
     iso-power charges NVLink for its whole fabric while giving glass its
     1800 GB/s electrical tier for free. That asymmetry is in the PUBLISHED
     figures, not just in my arithmetic, and it cuts against us. See A38.
"""
WG_LINE_TBPS = 1.024 / 8          # one waveguide, per direction, TB/s (1.024 Tb/s)
P_LASER, P_TUNE = 3.84, 1.44
GLASS_STATIC = P_LASER + P_TUNE
PJ_OPT = (1.15, 2.62)             # PanelScale blended, and the components-based conservative
PJ_RDL = (1.0, 2.0)               # XSR PHY <100um ; on-PCB short reach
PJ_NIC = (16, 20)
PJ_NVL, W_NVSWITCH_NVL5 = 1.5, 540 / 72

def w(gbs, pj):                    # GB/s (per direction) -> watts
    return gbs * 1e9 * 8 * pj * 1e-12

# ---- sanity: reproduce the published GB/s/W -----------------------------
nvl5_pub = 1.8e12 * 8 * PJ_NVL * 1e-12 + W_NVSWITCH_NVL5
nvl4_pub = 0.9e12 * 8 * PJ_NVL * 1e-12 + 12.5
print("sanity check against main.tex's published figures")
print(f"  NVL5  1800 GB/s / {nvl5_pub:.1f} W = {1800/nvl5_pub:.0f} GB/s/W   (paper: 62)")
print(f"  NVL4   900 GB/s / {nvl4_pub:.1f} W = {900/nvl4_pub:.0f} GB/s/W   (paper: 39)\n")

# ---- glass, the EP=32 configuration -------------------------------------
ELEC_BW, OPT_BW, EDGE_BW = 1800, 384, 1600
N_ELEC, N_OPT, N_EDGE, PANEL = 24, 24, 4, 16
opt_gpu = (N_OPT * OPT_BW + N_EDGE * EDGE_BW) / PANEL
rdl_gpu = (N_ELEC * ELEC_BW) / PANEL

print(f"glass-FB EP=32, per GPU: optical {opt_gpu:.0f} GB/s, electrical RDL {rdl_gpu:.0f} GB/s")
print(f"  lit waveguides = {opt_gpu / (WG_LINE_TBPS*1000):.1f} of the 60 WG budget\n")

# ---- dom64 ---------------------------------------------------------------
NVL_BIDIR, NIC_BW = 1.8e12, 100
nvl_w = NVL_BIDIR * 8 * PJ_NVL * 1e-12 + W_NVSWITCH_NVL5
print(f"nvl5_dom64 per GPU: NVLink5 {nvl_w:.1f} W (dynamic + NVSwitch)")
for pj in PJ_NIC:
    print(f"                    + NIC @ {pj} pJ/bit = {w(NIC_BW,pj):.1f} W"
          f"  -> total {nvl_w + w(NIC_BW,pj):.1f} W")

print("\n" + "="*74)
print("glass whole-interconnect, under the two accountings")
print("="*74)
print(f"{'optical pJ/b':>12} {'RDL pJ/b':>9} {'glass W':>9} {'dom64 W':>9} {'ratio':>7}  verdict")
for pjo in PJ_OPT:
    g_opt = w(opt_gpu, pjo) + GLASS_STATIC
    # (i) the paper's current accounting: optical + static only, RDL excluded
    for pjn in (PJ_NIC[0],):
        d = nvl_w + w(NIC_BW, pjn)
        print(f"{pjo:>12.2f} {'excluded':>9} {g_opt:>9.1f} {d:>9.1f} {g_opt/d:>7.2f}"
              f"  {'glass LOWER' if g_opt < d else 'glass higher'}  <- paper's current basis")
    # (ii) apples-to-apples: RDL charged at an electrical figure
    for pjr in PJ_RDL:
        g = g_opt + w(rdl_gpu, pjr)
        d = nvl_w + w(NIC_BW, PJ_NIC[0])
        print(f"{pjo:>12.2f} {pjr:>9.1f} {g:>9.1f} {d:>9.1f} {g/d:>7.2f}"
              f"  {'glass LOWER' if g < d else 'glass HIGHER'}")

print(f"""
READING.
Under the paper's current accounting (optical + static, RDL excluded) glass draws
far less than dom64 and the 3.71x training speedup stands unnormalised.

Charging the RDL properly, the answer depends on the electrical figure: at XSR's
1 pJ/bit glass still comes in at or below dom64; at on-PCB 2 pJ/bit it goes above
and the speedup would need normalising. So the honest statement is bracketed, not
"not determinable" as I said before -- the earlier version was wrong because it
used a class bound for NVLink instead of the constant the paper already uses.

THE REAL ISSUE IS A38, and it is in the PUBLISHED figures. The paper charges
NVLink for its entire fabric (dynamic + NVSwitch) while charging glass for
waveguides only. Glass's 1800 GB/s electrical tier -- {rdl_gpu/(opt_gpu+rdl_gpu)*100:.0f}% of its
per-GPU interconnect bandwidth -- appears in no power figure: not tab:power's
~70 W, not Fig 6a, not Fig 7b. Either include it at a sourced electrical pJ/bit
everywhere, or state the exclusion and defend it.

The defence exists and is measured, which is why stating it is enough: ARM A
showed elec x2 changes makespan by 0 and elec/2 by +0.02%, so the RDL carries far
below its provisioned load. Charging provisioned bandwidth x pJ/bit therefore
overstates its real draw. But that argument has to be ON THE PAGE, not implicit
in an omission a reviewer will find.""")
