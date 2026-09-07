"""Shared style for the DATE 2027 Glass-FB figures.

Conventions (from the fabric papers we compare against):
  * one colour per SYSTEM, kept identical in every figure (MixNet, FRED);
  * solid = simulated with queues, dashed = analytic / vendor-claim bound (our addition);
  * marker per system: o Glass-FB, s NVL-64, ^ HGX-8;
  * makespan in ms on a log axis when the range exceeds 5x (Rail-only), linear otherwise;
  * every bar/point carries its number when there are <= 8 of them (WATOS);
  * a second y-axis or an inset gives "speedup over <baseline>" (FRED normalises to the
    incumbent, MixNet to the best);
  * IEEE column 3.5 in / double column 7.16 in, 7-8 pt text, no titles inside the figure
    (the caption carries the sentence).
"""
import matplotlib as mpl

COL = {
    "glassfb":      "#1f6f8b",   # Glass-FB, port map (headline)
    "glassfb_mesh": "#8fbcd4",   # Glass-FB, 4-edge mesh (as first submitted)
    "glassfb_hier": "#0b3d4f",   # Glass-FB + gateway-aggregated A2A
    "nvl64_pkt":    "#7a0177",   # NVL-64, packet-level NVSwitch
    "nvl64":        "#7a0177",   # NVL-64, analytic island (dashed)
    "hgx8_pkt":     "#d95f0e",
    "hgx8":         "#d95f0e",
    "bound":        "#9a9a9a",
    "compute":      "#c9c9c9", "a2a_intra": "#4c9ac1", "a2a_inter": "#1f6f8b",
    "dp": "#b56a3c", "pp": "#e0b97a", "tail": "#b22222",
}
LABEL = {
    "glassfb": "Glass-FB", "glassfb_mesh": "Glass-FB (4-edge mesh)", "glassfb_hier": "Glass-FB + hier. A2A",
    "nvl64_pkt": "NVL-64 (queued NVSwitch)", "nvl64": "NVL-64 (vendor-claim bound)",
    "hgx8_pkt": "HGX-8 (queued NVSwitch)", "hgx8": "HGX-8 (bound)",
}
MARK = {"glassfb": "o", "glassfb_mesh": "o", "glassfb_hier": "o", "nvl64_pkt": "s", "nvl64": "s", "hgx8_pkt": "^", "hgx8": "^"}
DASH = {"nvl64": (3, 2), "hgx8": (3, 2)}
COL_W, DBL_W = 3.5, 7.16   # inches

def apply():
    mpl.rcParams.update({
        "font.size": 7.5, "axes.labelsize": 7.5, "axes.titlesize": 7.5, "legend.fontsize": 6.5,
        "xtick.labelsize": 6.5, "ytick.labelsize": 6.5, "axes.linewidth": 0.6,
        "xtick.major.width": 0.5, "ytick.major.width": 0.5, "lines.linewidth": 1.3,
        "lines.markersize": 3.5, "legend.frameon": False, "axes.grid": True, "grid.alpha": 0.25,
        "grid.linewidth": 0.4, "savefig.dpi": 300, "pdf.fonttype": 42, "ps.fonttype": 42,
        "font.family": "sans-serif", "font.sans-serif": ["Helvetica", "Arial", "DejaVu Sans"],
        "axes.spines.top": False, "axes.spines.right": False,
    })

def style_line(sysname):
    kw = dict(color=COL[sysname], marker=MARK.get(sysname, "o"), label=LABEL.get(sysname, sysname))
    if sysname in DASH: kw.update(linestyle="--", dashes=DASH[sysname], alpha=0.85, markerfacecolor="white")
    return kw
