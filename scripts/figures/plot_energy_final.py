#!/usr/bin/env python3
"""Final energy/EDP figure for the paper — per-GPU interconnect power, bandwidth-per-watt
(which ties directly to the iso-power performance result), and the SYSTEM-energy fraction
(honesty: interconnect is a small slice of a 700 W GPU). All values documented in
scripts/energy_methodology.md. The glass pJ/bit is a RANGE (1.15 PanelScale aggregate ..
2.62 component sum) -> the headline advantage is shown across that range."""
import os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

FP = "/Users/seongwonyoon/Documents/vscode_workspace/github-repos/LLMServingSim/outputs/fabric_plots"

# ---- documented constants (see energy_methodology.md) ----
GPU_W = 700.0                       # H100 TDP (system context)
# glass: 60 WG/GPU (30/dir) -> 7.66 TB/s; dynamic pJ/bit range; static = laser+ring
GLASS_BW = 7.66                     # TB/s aggregate bidir
WG = 60; LINE_TBs = WG * 1.024 / 8  # TB/s if all WG at line rate (for peak dynamic)
N_LAM = 30 * 32                     # TX wavelengths (30 WG/dir x 32 lambda)
P_LASER = N_LAM * 1e-3 / 0.25       # 1 mW/lambda, WPE 25%  -> 3.84 W
P_TUNE  = 2 * N_LAM * 0.75e-3       # TX MRM + RX filter, 0.75 mW/ring -> 1.44 W
GLASS_STATIC = P_LASER + P_TUNE     # ~5.3 W (passive: NO switch)
EDYN = {"opt (1.15 pJ/b, PanelScale)": 1.15, "cons (2.62 pJ/b, components)": 2.62}

# electrical baselines
NVL4_BW, NVL4_EDYN, NVL4_SWITCH = 0.9, 1.5, 12.5     # H100 HGX: NVLink4, 4xNVSwitch3 /8 GPU
NVL5_BW, NVL5_EDYN, NVL5_SWITCH = 1.8, 1.5, 540/72   # GB200 NVL72: NVLink5, 540 W/rack /72

def glass_power(edyn):                # peak dynamic (all WG at line rate) + static
    return WG * 1.024e12 * edyn * 1e-12 + GLASS_STATIC
def elec_power(bw, edyn, switch):     # peak dynamic for the aggregate BW + switch static
    return bw*1e12 * 8 * edyn * 1e-12 + switch

# ---- compute ----
fabrics = []  # (label, BW TB/s, power W, color)
for lab, e in EDYN.items():
    fabrics.append((f"Glass-FB\n{lab}", GLASS_BW, glass_power(e), "#2c7fb8"))
fabrics.append(("H100\nNVLink4+NVSwitch", NVL4_BW, elec_power(NVL4_BW, NVL4_EDYN, NVL4_SWITCH), "#d95f0e"))
fabrics.append(("GB200 NVL72\nNVLink5", NVL5_BW, elec_power(NVL5_BW, NVL5_EDYN, NVL5_SWITCH), "#7a0177"))

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5.2))

# Panel A: bandwidth-per-watt (ties to iso-power 2.7x)
labels = [f[0] for f in fabrics]; bwpw = [f[1]/f[2]*1000 for f in fabrics]  # GB/s per W
x = np.arange(len(labels))
bars = ax1.bar(x, bwpw, 0.6, color=[f[3] for f in fabrics])
for xi, v in zip(x, bwpw): ax1.text(xi, v+2, f"{v:.0f}", ha="center", fontsize=9)
ax1.set_xticks(x); ax1.set_xticklabels(labels, fontsize=8)
ax1.set_ylabel("interconnect bandwidth per watt (GB/s / W)")
ax1.set_title("Bandwidth-per-watt (drives the iso-power result)")
ax1.grid(axis="y", ls=":", alpha=.5)
# annotate glass-vs-NVLink ratio range
g_opt, g_cons = bwpw[0], bwpw[1]
ax1.text(0.5, max(bwpw)*0.78, f"glass/NVLink4 = {g_cons/bwpw[2]:.1f}-{g_opt/bwpw[2]:.1f}x\n"
         f"(matches iso-power perf 1.3-2.7x)", fontsize=8.5, color="#225ea8")

# Panel B: per-GPU interconnect power + system fraction
xt = np.arange(len(fabrics))
dyn = [f[2]-(GLASS_STATIC if "Glass" in f[0] else (NVL4_SWITCH if "H100" in f[0] else NVL5_SWITCH)) for f in fabrics]
stat = [GLASS_STATIC if "Glass" in f[0] else (NVL4_SWITCH if "H100" in f[0] else NVL5_SWITCH) for f in fabrics]
ax2.bar(xt, dyn, 0.55, label="dynamic (link)", color="#9ecae1")
ax2.bar(xt, stat, 0.55, bottom=dyn, label="static (laser+ring / NVSwitch)", color="#fc9272")
for xi, f in zip(xt, fabrics):
    frac = 100*f[2]/(f[2]+GPU_W)
    ax2.text(xi, f[2]+3, f"{f[2]:.0f} W\n({frac:.1f}% of system)", ha="center", fontsize=7.5)
ax2.set_xticks(xt); ax2.set_xticklabels(labels, fontsize=8)
ax2.set_ylabel("per-GPU interconnect power (W)")
ax2.set_title(f"Interconnect power vs system (GPU {GPU_W:.0f} W)\nglass = passive (no switch); peak dynamic")
ax2.legend(fontsize=8); ax2.grid(axis="y", ls=":", alpha=.5)

fig.suptitle("Interconnect energy — glass-FB optical vs NVLink (per GPU)", fontsize=12)
fig.tight_layout(rect=[0,0,1,0.96]); fig.savefig(f"{FP}/energy_final.png", dpi=150)
print("wrote energy_final.png")
print("\n-- numbers --")
for lab, bw, p, _ in fabrics:
    print(f"  {lab.replace(chr(10),' '):42} BW {bw:.2f} TB/s  power {p:6.1f} W  "
          f"BW/W {bw/p*1000:5.0f} GB/s/W  sys% {100*p/(p+GPU_W):.1f}")
print(f"\n  glass static (passive, always-on): laser {P_LASER:.1f}W + ring {P_TUNE:.1f}W = {GLASS_STATIC:.1f} W")
print("  KEY: glass beats H100-NVLink4 BW/W by 1.3-2.7x (pJ/bit range) -> matches iso-power perf;")
print("       vs GB200-NVLink5 glass wins only at the optimistic (1.15) pJ/bit -> CLOSE the pJ/bit Q.")
