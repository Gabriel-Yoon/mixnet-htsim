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
The static term, hop-bytes and the NVSwitch fabrics are unchanged; power_tiers.csv's
link_J_iter columns for glassfb_* therefore no longer match the paper and are NOT read.
"""
ELEC_PJ = (0.60, 1.15)
OPT_PJ = (1.15, 2.62)

def J(nbytes, pj):
    return float(nbytes) * 8 * pj * 1e-12

def glass_tiers(r):
    """[(tier, J_lo, J_hi)] for one power_tiers.csv glass row: electrical, intra-panel optical, ports."""
    be, bo, bi = float(r["bytes_elec"]), float(r["bytes_opt"]), float(r["bytes_inter"])
    return [("elec", J(be, ELEC_PJ[0]), J(be, ELEC_PJ[1])),
            ("opt", J(bo, OPT_PJ[0]), J(bo, OPT_PJ[1])),
            ("inter", J(bi, OPT_PJ[0]), J(bi, OPT_PJ[1]))]

def glass_static(r):
    """(lo, hi): 5.3 W/panel (100G lanes) .. 9.12 W/panel (200G lanes)."""
    return float(r["static_J_iter"]), float(r.get("static_J_iter_200G") or r["static_J_iter"])

def glass_total(r):
    t = glass_tiers(r); s = glass_static(r)
    return sum(x[1] for x in t) + s[0], sum(x[2] for x in t) + s[1]

def pkt_total(r):
    return (float(r["link_J_iter_lo"]) + float(r["static_J_iter_lo"]),
            float(r["link_J_iter_hi"]) + float(r["static_J_iter_hi"]))
