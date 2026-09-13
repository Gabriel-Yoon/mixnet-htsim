#!/usr/bin/env python3
"""Paper table: interconnect energy per iteration, every term shown (power_tiers.csv for Glass-FB
at the 200G/lane design point, power_tiers_pkt.csv for NVL72 = nvl64_pkt_s1 and HGX-8).
Bytes are hop-bytes (bytes x hops of that tier on the flow's route); link J = bytes x 8 x pJ/bit,
with Glass-FB's tiers charged per Hsueh et al. Table 1 (energy_consts.py: electrical 0.6-1.15,
optical 1.15-2.62 pJ/b); static J = static W x iteration.
Env: PAPER_RES, OUT. Writes energy_table.tex."""
import csv, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from energy_consts import glass_tiers, glass_static, glass_total, ELEC_PJ, OPT_PJ
RES = os.environ.get("PAPER_RES", os.path.join(os.path.dirname(__file__), "..", "..", "experiments", "results", "paper"))
OUT = os.environ.get("OUT", ".")
EPS = [16, 32, 64, 128]
g = {int(r["ep"]): r for r in csv.DictReader(open(os.path.join(RES, "power_tiers.csv"))) if r["system"] == "glassfb_800"}
n = {(r["system"], int(r["ep"])): r for r in csv.DictReader(open(os.path.join(RES, "power_tiers_pkt.csv")))}
def TB(b): return "%.2f" % (float(b) / 1e12)
def J(lo, hi=None, d=1):
    f = "%%.%df" % d
    return (f % float(lo)) if hi is None or abs(float(lo) - float(hi)) < 10 ** (-d) / 2 else (f + "--" + f) % (float(lo), float(hi))
def tierJ(bytes_, pj_lo, pj_hi, hops=1):
    b = float(bytes_) * hops * 8e-12
    return b * pj_lo, b * pj_hi
rows = []
def row(label, cells, bold=False):
    lab = r"\textbf{%s}" % label if bold else label
    rows.append(lab + " & " + " & ".join(cells) + r" \\")
# ---- Glass-FB
glo, ghi = OPT_PJ; elo, ehi = ELEC_PJ
rows.append(r"\multicolumn{5}{@{}l}{\textbf{\glassfb{}} (200G/lane ports; iteration %s~ms)} \\" % " / ".join("%.1f" % float(g[e]["makespan_ms"]) for e in EPS))
row(r"hop-bytes, electrical RDL (TB)", [TB(g[e]["bytes_elec"]) for e in EPS])
row(r"hop-bytes, intra-panel optical (TB)", [TB(g[e]["bytes_opt"]) for e in EPS])
row(r"hop-bytes, inter-panel ports (TB)", [TB(g[e]["bytes_inter"]) for e in EPS])
row(r"link J, RDL tier @ %.2f--%.2f pJ/bit" % (elo, ehi), [J(*tierJ(g[e]["bytes_elec"], elo, ehi)) for e in EPS])
row(r"link J, optical tiers @ %.2f--%.2f pJ/bit" % (glo, ghi), [J(*tierJ(float(g[e]["bytes_opt"]) + float(g[e]["bytes_inter"]), glo, ghi)) for e in EPS])
row(r"link J, total", [J(sum(t[1] for t in glass_tiers(g[e])), sum(t[2] for t in glass_tiers(g[e]))) for e in EPS])
row(r"static W: %s~W/panel $\times$ panels" % g[16]["static_laser_tune_W_per_panel"], ["%.0f" % (float(g[e]["static_laser_tune_W_per_panel"]) * (int(e) * 8 / 16)) for e in EPS])
row(r"static J (5.3~W/panel; 9.12 at 200G/lane)", [J(g[e]["static_J_iter"], g[e]["static_J_iter_200G"]) for e in EPS])
row(r"total J", [J(*glass_total(g[e])) for e in EPS], bold=True)
rows.append(r"\midrule")
# ---- NVSwitch fabrics
for sysname, name in (("nvl64_pkt_s1", "NVL72"), ("hgx8_pkt", "HGX-8")):
    rr = {e: n[(sysname, e)] for e in EPS}
    r0 = rr[16]; nlo, nhi, nic = float(r0["nvlink_pj_bit_lo"]), float(r0["nvlink_pj_bit_hi"]), float(r0["nic_pj_bit"])
    hd, hc = int(r0["hops_in_domain"]), int(r0["hops_cross"])
    rows.append(r"\multicolumn{5}{@{}l}{\textbf{%s} (iteration %s~ms)} \\" % (name, " / ".join("%.1f" % float(rr[e]["makespan_ms"]) for e in EPS)))
    row(r"hop-bytes in domain (TB; %d NVLink hops per flow)" % hd, [TB(rr[e]["bytes_in_domain"]) for e in EPS])
    row(r"hop-bytes on NICs (TB; %d hop per flow)" % hc, [TB(rr[e]["bytes_nic"]) for e in EPS])
    row(r"link J, NVLink @ %.2f--%.1f pJ/bit" % (nlo, nhi), [J(*tierJ(rr[e]["bytes_in_domain"], nlo, nhi)) for e in EPS])
    row(r"link J, NIC @ %.0f pJ/bit" % nic, [J(*tierJ(rr[e]["bytes_nic"], nic, nic)) for e in EPS])
    row(r"link J, total", [J(rr[e]["link_J_iter_lo"], rr[e]["link_J_iter_hi"]) for e in EPS])
    row(r"static W: %s--%s~W/GPU $\times$ GPUs" % (r0["nvs_static_W_per_gpu_lo"], r0["nvs_static_W_per_gpu_hi"]), ["%.0f--%.0f" % (float(r0["nvs_static_W_per_gpu_lo"]) * int(rr[e]["nodes"]), float(r0["nvs_static_W_per_gpu_hi"]) * int(rr[e]["nodes"])) for e in EPS])
    row(r"static J", [J(rr[e]["static_J_iter_lo"], rr[e]["static_J_iter_hi"], 0) for e in EPS])
    row(r"total J", [J(float(rr[e]["link_J_iter_lo"]) + float(rr[e]["static_J_iter_lo"]), float(rr[e]["link_J_iter_hi"]) + float(rr[e]["static_J_iter_hi"]), 0) for e in EPS], bold=True)
    if sysname == "nvl64_pkt_s1": rows.append(r"\midrule")
tex = "\n".join([
 r"\begin{table*}[tb]", r"\centering", r"\footnotesize", r"\setlength{\tabcolsep}{5pt}",
 r"\caption{Interconnect energy per training iteration, every term. Bytes are hop-bytes from each topology's own path classification of the quoted run (a flow crossing two hops of a tier is charged twice); link J $=$ bytes $\times$ 8 $\times$ pJ/bit at the favorable--conservative ends; static J $=$ static power $\times$ the quoted iteration. GPUs $=$ 8$\times$EP; panels $=$ GPUs/16.}",
 r"\label{tab:energy}",
 r"\begin{tabular}{@{}lrrrr@{}}", r"\toprule",
 r"Term & EP$=$16 & EP$=$32 & EP$=$64 & EP$=$128 \\", r"\midrule",
 *rows, r"\bottomrule", r"\end{tabular}", r"\end{table*}", ""])
open(os.path.join(OUT, "energy_table.tex"), "w").write(tex); print("wrote energy_table.tex (%d rows)" % len(rows))
