#!/usr/bin/env python3
"""Fig 1(b): the 4x4 Glass-FB panel, top view.

Draws every FB link of one highlighted GPU (its whole row and column) with the three
distance classes -- distance-1 electrical RDL, distance-2 optical waveguide at L1,
distance-3 optical at L2 -- as arcs whose bow grows with depth, the remaining FB links
as a faint lattice, the 16 MTP-16 ports (four per edge, one per GPU), and the external
laser source at a corner. Output: fig_panel.png / fig_panel.pdf in OUT (default .).

    python3 draw_panel.py
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle, Circle
from matplotlib.path import Path
import matplotlib.patches as mpatches

OUT = os.environ.get("OUT", ".")

# palette (matches paper_style.py: glass teal family, copper for electrical)
C_TILE = "#eef2f4"; C_TILE_EDGE = "#8a9399"; C_SRC = "#d9f1ec"; C_SRC_EDGE = "#1f6f8b"
C_D1 = "#b5651d"          # electrical RDL (copper)
C_D2 = "#2a9d8f"          # optical L1
C_D3 = "#e9a23b"          # optical L2
C_PORT = "#3a4a54"; C_PORT_FACE = "#5b8fa8"
C_ELS = "#b23a8a"; C_LATTICE = "#c9d1d6"

N = 4
PITCH = 1.0
TILE = 0.62
SRC = (0, 3)              # (col, row) of the highlighted GPU: bottom-left corner, so its row and column each show d1, d2, d3

def center(c, r):
    return (c * PITCH, (N - 1 - r) * PITCH)

fig, ax = plt.subplots(figsize=(3.6, 3.9), dpi=300)
ax.set_aspect("equal"); ax.axis("off")

# faint lattice: every row/column FB link of every GPU (all pairs in a row, all pairs in a column)
for r in range(N):
    for a in range(N):
        for b in range(a + 1, N):
            (x1, y1), (x2, y2) = center(a, r), center(b, r)
            ax.plot([x1, x2], [y1, y2], color=C_LATTICE, lw=0.9, zorder=1, solid_capstyle="round")
for c in range(N):
    for a in range(N):
        for b in range(a + 1, N):
            (x1, y1), (x2, y2) = center(c, a), center(c, b)
            ax.plot([x1, x2], [y1, y2], color=C_LATTICE, lw=0.9, zorder=1, solid_capstyle="round")

def arc(p, q, dist, horizontal):
    """One FB link of the source: straight copper for distance-1, arcs bowing away from the
    grid for distance 2/3 (deeper layer -> larger bow), so the three classes never overlap."""
    (x1, y1), (x2, y2) = p, q
    if dist == 1:
        ax.plot([x1, x2], [y1, y2], color=C_D1, lw=4.2, zorder=3, solid_capstyle="round")
        return
    col, lw = (C_D2, 3.0) if dist == 2 else (C_D3, 3.0)
    bow = 0.30 if dist == 2 else 0.55
    if horizontal:   # bow below the row (toward the panel's south edge)
        ctrl = ((x1 + x2) / 2, y1 - bow)
    else:            # bow to the left of the column (toward the west edge)
        ctrl = (x1 - bow, (y1 + y2) / 2)
    path = Path([p, ctrl, q], [Path.MOVETO, Path.CURVE3, Path.CURVE3])
    ax.add_patch(mpatches.PathPatch(path, facecolor="none", edgecolor=col, lw=lw, zorder=3, capstyle="round"))

sc, sr = SRC
for c in range(N):
    if c == sc: continue
    arc(center(sc, sr), center(c, sr), abs(c - sc), horizontal=True)
for r in range(N):
    if r == sr: continue
    arc(center(sc, sr), center(sc, r), abs(r - sr), horizontal=False)

# tiles
for r in range(N):
    for c in range(N):
        x, y = center(c, r)
        is_src = (c, r) == SRC
        ax.add_patch(FancyBboxPatch((x - TILE / 2, y - TILE / 2), TILE, TILE,
                                    boxstyle="round,pad=0,rounding_size=0.08",
                                    facecolor=C_SRC if is_src else C_TILE,
                                    edgecolor=C_SRC_EDGE if is_src else C_TILE_EDGE,
                                    lw=1.8 if is_src else 1.0, zorder=5))
        ax.text(x, y + 0.06, "GPU", ha="center", va="center", fontsize=6.5,
                color="#1f2a30" if is_src else "#5a6670", fontweight="bold" if is_src else "normal", zorder=6)
        ax.text(x, y - 0.14, "PIC", ha="center", va="center", fontsize=4.6, color="#7a8790", zorder=6)

# 16 MTP-16 ports on the panel boundary, one per GPU, four per edge: the top row feeds the
# north edge, the bottom row the south edge, and the two middle rows feed west (columns 0-1)
# and east (columns 2-3). A thin lead runs from each tile to its port.
PAD = 0.95
port_w, port_h = 0.26, 0.09
def port(c, r):
    x, y = center(c, r)
    L, R, B, T = -PAD, (N - 1) * PITCH + PAD, -PAD, (N - 1) * PITCH + PAD
    if r == 0:            side, px, py = "N", x, T
    elif r == N - 1:      side, px, py = "S", x, B
    elif c <= 1:          side, px, py = "W", L, y + (0.16 if c == 0 else -0.16)
    else:                 side, px, py = "E", R, y + (0.16 if c == N - 1 else -0.16)
    lead = dict(color=C_PORT, lw=0.9, zorder=2, alpha=0.85)
    if side in ("N", "S"):
        y0 = y + TILE / 2 if side == "N" else y - TILE / 2
        ax.plot([x, x], [y0, py], **lead)
        ax.add_patch(Rectangle((px - port_w / 2, py - port_h / 2), port_w, port_h, facecolor=C_PORT_FACE, edgecolor=C_PORT, lw=0.6, zorder=4))
    else:
        x0 = x - TILE / 2 if side == "W" else x + TILE / 2
        ax.plot([x0, px], [py, py], **lead)
        ax.add_patch(Rectangle((px - port_h / 2, py - port_w / 2), port_h, port_w, facecolor=C_PORT_FACE, edgecolor=C_PORT, lw=0.6, zorder=4))
for r in range(N):
    for c in range(N):
        port(c, r)

# external laser source at the south-west corner, feeding the panel's distribution waveguide
lx, ly = -1.05, -1.25
ax.add_patch(FancyBboxPatch((lx - 0.22, ly - 0.14), 0.44, 0.28, boxstyle="round,pad=0,rounding_size=0.05",
                            facecolor=C_ELS, edgecolor="none", zorder=5))
ax.text(lx, ly, "ELS", ha="center", va="center", fontsize=6, color="white", fontweight="bold", zorder=6)
ax.plot([lx + 0.16, -TILE / 2 - 0.02], [ly + 0.12, -TILE / 2 + 0.02], color=C_ELS, lw=1.2, ls=(0, (2, 1.5)), zorder=2)

# labels on the source's links: the row shows all three classes side by side below the bottom row
ax.text(0.5, 0.0 + 0.10, "d1", ha="center", va="bottom", fontsize=5.8, color=C_D1, fontweight="bold", zorder=7)
ax.text(1.0, 0.0 - 0.27, "d2 / L1", ha="center", va="top", fontsize=5.4, color=C_D2, fontweight="bold", zorder=7)
ax.text(1.5, 0.0 - 0.52, "d3 / L2", ha="center", va="top", fontsize=5.4, color=C_D3, fontweight="bold", zorder=7)
# panel outline
pad = PAD
ax.add_patch(Rectangle((-pad, -pad), (N - 1) * PITCH + 2 * pad, (N - 1) * PITCH + 2 * pad,
                       facecolor="none", edgecolor="#9aa5ad", lw=0.8, ls=(0, (3, 2)), zorder=0))
ax.text((N - 1) * PITCH / 2, (N - 1) * PITCH + pad + 0.14, "16 MTP-16 ports, four per edge, 400 GB/s each",
        ha="center", va="bottom", fontsize=5.6, color=C_PORT)

# legend
h = [mpatches.Patch(color=C_D1, label="distance-1: electrical RDL, 1800 GB/s"),
     mpatches.Patch(color=C_D2, label="distance-2: glass waveguide L1, 384 GB/s"),
     mpatches.Patch(color=C_D3, label="distance-3: glass waveguide L2, 384 GB/s"),
     mpatches.Patch(color=C_LATTICE, label="the other GPUs' row/column links"),
     mpatches.Patch(color=C_PORT_FACE, label="MTP-16 port (one per GPU)")]
ax.legend(handles=h, loc="upper center", bbox_to_anchor=(0.5, -0.06), fontsize=5.2, frameon=False, ncol=1, handlelength=1.6, borderaxespad=0)

ax.set_xlim(-1.35, (N - 1) * PITCH + 1.15)
ax.set_ylim(-1.5, (N - 1) * PITCH + 1.45)
fig.tight_layout(pad=0.2)
for ext in ("png", "pdf"):
    fig.savefig(os.path.join(OUT, f"fig_panel.{ext}"), bbox_inches="tight", pad_inches=0.02)
print("wrote fig_panel.png/pdf")
