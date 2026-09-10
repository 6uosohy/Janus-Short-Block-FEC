# Fig. 1 — AWGN five-FEC BLER. Same tab10 palette, markers, and legend wording as
# Fig. 3; no in-figure title; vector PDF output.
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
# IEEE PDF eXpress rejects Type 3 fonts, which is the matplotlib default.
# Force Type 42 (TrueType).
matplotlib.rcParams["pdf.fonttype"] = 42
matplotlib.rcParams["ps.fonttype"] = 42
import matplotlib.pyplot as plt
from scipy.io import loadmat

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
MAT = os.path.join(_ROOT, "data", "fhbfsk_awgn", "fhbfsk_5fec_results.mat")
OUT = os.path.join(_ROOT, "figures")
os.makedirs(OUT, exist_ok=True)

d = loadmat(MAT, squeeze_me=True, struct_as_record=False)
ebn0 = np.asarray(d["fhbfsk_cfg"].ebn0_db, dtype=float).ravel()
bler = np.atleast_2d(np.asarray(d["bler"], dtype=float))

# Same tab10 colours, markers, and labels as Fig. 3.
# Mode order: Conv, Turbo, LDPC, Polar-Fix, Polar-Adp.
COLORS = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd"]
MARKERS = ["o", "s", "D", "^", "v"]
LABELS = ["Conv", "Turbo", "LDPC", "Polar-Fix (L=8)", "Polar-Adp (ASCL)"]

# 511.07 x 348.99 pt at 72 dpi — the size the paper's Fig. 1 occupies.
fig, ax = plt.subplots(figsize=(511.07293701171875 / 72.0, 348.9888000488281 / 72.0))

# The AWGN sweep runs 0-12 dB, but every code is still at BLER 1 below 5 dB,
# so the figure starts where the curves separate.
XMIN, XMAX = 5.0, 12.0
YFLOOR = 2e-4
# No confidence band here: over AWGN every point carries 300 frame errors, so the
# Wilson interval is narrower than the line width. Fig. 3 shades it because the
# UWA tail runs out of errors and the interval opens up.
for i in range(bler.shape[0]):
    v = bler[i] > 0
    ax.plot(ebn0[v], bler[i][v], MARKERS[i] + "-", color=COLORS[i],
            markerfacecolor="none", markersize=5, linewidth=1.4, label=LABELS[i])

# Reference lines and their labels, placed at the left edge; the legend sits in
# the lower left, well below both.
for y, txt in [(1e-1, r"BLER=$10^{-1}$"), (1e-2, r"BLER=$10^{-2}$")]:
    ax.axhline(y, color="0.55", linestyle="--", linewidth=0.8, zorder=0)
    ax.text(XMIN + 0.1, y * 1.12, txt, color="0.40", fontsize=9, va="bottom")

ax.set_yscale("log")
ax.set_xlim(XMIN, XMAX)
ax.set_ylim(YFLOOR, 1.0)
ax.set_xlabel(r"$E_b/N_0$ (dB)", fontsize=11)
ax.set_ylabel("BLER", fontsize=11)
ax.grid(True, which="major", color="0.85", linewidth=0.6)
ax.grid(True, which="minor", color="0.93", linewidth=0.4)
ax.tick_params(labelsize=10)
ax.legend(loc="lower left", fontsize=10, framealpha=0.95)
fig.tight_layout(pad=0.7)

pdf = os.path.join(OUT, "fhbfsk_awgn_5fec_bler_ci_12dB.pdf")
fig.savefig(pdf)
fig.savefig(os.path.join(OUT, "fhbfsk_awgn_5fec_bler_ci_12dB.png"), dpi=200)
plt.close(fig)
print("saved:", pdf)
print("ylim floor=%.3g (lowest BLER=%.4f)" % (YFLOOR, bler[bler > 0].min()))
