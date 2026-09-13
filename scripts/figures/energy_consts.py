"""Per-tier link energy charged to Glass-FB in the DATE 2027 paper (single source for every
energy figure and table). All values are from Hsueh et al., "Panel-Scale Reconfigurable
Photonic Interconnects for Scalable AI Computation" (IEEE OJ-SSCS 2025, arXiv:2508.06079),
Table 1, at 32 Gb/s per lane:
  electrical RDL tier (distance-1): 0.60 pJ/b  UCIe PHY, TX+RX            (favorable end)
                                    1.15 pJ/b  XSR SerDes PHY, TX/RX avg.  (conservative end)
  optical tiers (distance>=2, ports): 1.15 pJ/b  32-wavelength WDM photonic link, TX/RX avg.
                                    2.62 pJ/b  conservative end, a 2.3x margin on 1.15 (no source)
Replaces (2026-09-13) the producer convention of scripts/tier_energy.py, which charged the
electrical tier the optical bracket plus an unsourced 1.0 pJ/b RDL adder (2.15-3.62 pJ/b).
Hop-bytes and the NVSwitch fabrics are unchanged; the static term is recomputed below; power_tiers.csv's
link_J_iter columns for glassfb_* therefore no longer match the paper and are NOT read.
"""
# Single values (2026-09-13, user decision: no favorable/conservative brackets in the paper).
# The (lo, hi) tuple shape is kept so callers are unchanged; lo == hi everywhere.
#   electrical RDL tier: 1.15 pJ/b, Hsueh Table 1 XSR SerDes PHY (a ~30 mm tile-to-tile link is
#                        an XSR-class link; the 0.60 UCIe PHY is for millimetre die-to-die reach)
#   optical tiers:       1.15 pJ/b, Hsueh Table 1 32-wavelength WDM photonic link (2.62 margin dropped)
#   NVLink:              5.0 pJ/b, HotI'25 (Lightmatter) 224G-LR SerDes figure, scale-up class <5
#                        (1.55 was a 112G XSR SerDes, not an NVLink SerDes)
#   800G NIC:            16 pJ/b, HotI'25 Table I scale-out class
#   copper long links:   16 pJ/b, same scale-out class (copper_energy.csv carried 16-20)
#   NVSwitch static:     7.5 W/GPU for NVL72, 12.5 W/GPU for HGX-8 (was a 7.5-12.5 bracket for both)
ELEC_PJ = (1.15, 1.15)
OPT_PJ = (1.15, 1.15)
NVLINK_PJ = 5.0
NIC_PJ = 16.0
COPPER_PJ = 16.0
NVS_STATIC_W_PER_GPU = {"nvl64_pkt_s1": 7.5, "hgx8_pkt": 12.5}

# Static term: external laser + ring tuning for the carriers the 4x4 panel actually modulates
# (corrected 2026-09-13; the earlier 5.3 / 9.12 W per panel applied ONE GPU's 960-wavelength
# budget to a whole 16-GPU panel, an 8.1x undercount (7808 / 960 carriers) -- the thermal deck already charged the
# 1.44 W of tuning per tile). Lit transmit carriers at the 200G/lane design point:
#   intra-panel: 24 distance>=2 links x 3 waveguides x 2 directions = 144 one-way waveguides
#   ports:       16 GPUs x 6.25 waveguides of egress (800 GB/s at 128 GB/s per waveguide) = 100
#   carriers:    (144 + 100) x 32 wavelengths = 7808
# laser: 1 mW per carrier behind a 25% wall-plug laser (Hsueh et al. inject 0.5 mW per carrier);
# tuning: two rings per carrier (TX modulator, RX filter) at 0.75 mW. Budget assumptions.
CARRIERS_PER_PANEL = (24 * 3 * 2 + 16 * 6.25) * 32
LASER_W_PER_PANEL = CARRIERS_PER_PANEL * 1e-3 / 0.25
TUNE_W_PER_PANEL = CARRIERS_PER_PANEL * 2 * 0.75e-3
STATIC_W_PER_PANEL = LASER_W_PER_PANEL + TUNE_W_PER_PANEL

def J(nbytes, pj):
    return float(nbytes) * 8 * pj * 1e-12

def glass_tiers(r):
    """[(tier, J_lo, J_hi)] for one power_tiers.csv glass row: electrical, intra-panel optical, ports."""
    be, bo, bi = float(r["bytes_elec"]), float(r["bytes_opt"]), float(r["bytes_inter"])
    return [("elec", J(be, ELEC_PJ[0]), J(be, ELEC_PJ[1])),
            ("opt", J(bo, OPT_PJ[0]), J(bo, OPT_PJ[1])),
            ("inter", J(bi, OPT_PJ[0]), J(bi, OPT_PJ[1]))]

def glass_static(r):
    """(lo, hi) static J per iteration: STATIC_W_PER_PANEL x panels x iteration (no bracket)."""
    j = STATIC_W_PER_PANEL * (float(r["nodes"]) / 16) * float(r["makespan_ms"]) / 1e3
    return j, j

def glass_total(r):
    t = glass_tiers(r); s = glass_static(r)
    return sum(x[1] for x in t) + s[0], sum(x[2] for x in t) + s[1]

def pkt_tiers(r):
    """[(tier, J, J)] for an NVSwitch row: in-domain NVLink hop-bytes and NIC hop-bytes."""
    a = J(r["bytes_in_domain"], NVLINK_PJ); b = J(r["bytes_nic"], NIC_PJ)
    return [("nvlink", a, a), ("nic", b, b)]

def pkt_static(r):
    j = NVS_STATIC_W_PER_GPU[r["system"]] * float(r["nodes"]) * float(r["makespan_ms"]) / 1e3
    return j, j

def pkt_total(r):
    t = pkt_tiers(r); s = pkt_static(r)
    return sum(x[1] for x in t) + s[0], sum(x[2] for x in t) + s[1]
