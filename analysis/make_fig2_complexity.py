# Fig. 2 — decoding complexity, two panels: the analytic per-frame operation
# count for all five decoders, and the effective count vs Eb/N0 where the four
# fixed-cost decoders are flat lines and Adaptive-SCL falls with SNR.
# No in-figure titles; vector PDF output.
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
MAT = os.path.join(_ROOT, "data", "fhbfsk_awgn", "ascl_profile.mat")
OUT = os.path.join(_ROOT, "figures")
os.makedirs(OUT, exist_ok=True)

d = loadmat(MAT, squeeze_me=True, struct_as_record=False)
ebn0 = np.asarray(d["ebn0_db"], dtype=float).ravel()      # 5:0.5:12
avg_attempts = np.asarray(d["avg_attempts"], dtype=float).ravel()
L_max = int(d["L"])                                        # 8
L0 = int(d["L0"])                                          # 4

# Analytic per-frame operation counts (K = 64, E = 144, N = 128).
N, LOGN = 128, 7
E, K = 144, 64
v, vT = 9, 3
ops_conv = 2 ** (v - 1) * E             # 36,864  Viterbi over 2^8 states
ops_turbo = 6 * 2 * 2 ** vT * K         #  6,144  6 iterations, two max-log-MAP passes
ops_ldpc = 50 * 3 * E                   # 21,600  50 min-sum iterations, column weight 3
ops_polar_fix = L_max * N * LOGN        #  7,168  fixed list of 8
ops_ascl_best = L0 * N * LOGN           #  3,584  adaptive decoder that never expands

# Adaptive-SCL: the first pass always costs L0; a CRC failure (probability
# p_expand) buys a second pass at L_max.
p_expand = np.maximum(avg_attempts - 1.0, 0.0)
ops_ascl = (L0 + p_expand * L_max) * N * LOGN

# tab10, matching Fig. 1 and Fig. 3 for the four codes they share; ASCL takes
# tab10's cyan so it reads as a distinct, adaptive quantity.
C_CONV = "#1f77b4"
C_TURBO = "#ff7f0e"
C_LDPC = "#2ca02c"
C_PFIX = "#9467bd"
C_ASCL = "#17becf"

# 566.28 x 494.14 pt at 72 dpi — the size the paper's Fig. 2 occupies.
fig, (ax1, ax2) = plt.subplots(
    2, 1, figsize=(566.2767333984375 / 72.0, 494.14385986328125 / 72.0),
    gridspec_kw={"height_ratios": [5, 6]})

# --- Top panel: analytic operation counts -------------------------------
names = ["Conv\n(Viterbi)", "Turbo\n(MAP$\\times$6)", "LDPC\n(NMS$\\times$50)",
         "Polar SCL\n($L$=8)", "Polar ASCL\n($L_0$=4, best)"]
ops = np.array([ops_conv, ops_turbo, ops_ldpc, ops_polar_fix, ops_ascl_best], float)
colors = [C_CONV, C_TURBO, C_LDPC, C_PFIX, C_ASCL]

ax1.bar(np.arange(5), ops / 1000.0, width=0.6, color=colors)
for k, val in enumerate(ops):
    ax1.text(k, val / 1000.0 + 1.0, f"{int(val):,}",
             ha="center", fontsize=8, fontweight="bold")
ax1.set_xticks(np.arange(5))
ax1.set_xticklabels(names, fontsize=9)
ax1.set_ylabel("Operations per Frame ($\\times 10^3$)", fontsize=11)
ax1.set_ylim(0, ops.max() / 1000.0 * 1.12)
ax1.grid(True, axis="y", color="0.85", linewidth=0.6)
ax1.set_axisbelow(True)

# --- Bottom panel: effective cost vs Eb/N0 ------------------------------
x0, x1 = ebn0.min(), ebn0.max()
for val, col in ((ops_conv, C_CONV), (ops_turbo, C_TURBO),
                 (ops_ldpc, C_LDPC), (ops_polar_fix, C_PFIX)):
    ax2.plot([x0, x1], [val / 1000.0] * 2, "--", color=col, linewidth=1.4)
ax2.plot(ebn0, ops_ascl / 1000.0, "-o", color=C_ASCL, linewidth=2.0,
         markersize=4, markerfacecolor=C_ASCL)

below = ops_ascl < ops_turbo
if below.any():
    ax2.fill_between(ebn0[below], ops_ascl[below] / 1000.0,
                     ops_turbo / 1000.0, color=C_ASCL, alpha=0.15, linewidth=0)

# Inline labels just past the right end of the data.
x_label = x1 + 0.15
for val, col, txt in ((ops_conv, C_CONV, "Conv"), (ops_ldpc, C_LDPC, "LDPC"),
                      (ops_polar_fix, C_PFIX, "Polar-Fix"),
                      (ops_turbo, C_TURBO, "Turbo")):
    ax2.text(x_label, val / 1000.0, txt, color=col, fontsize=8,
             fontweight="bold", va="center")

pct_of_turbo = ops_ascl_best / ops_turbo * 100.0
ax2.text(x1 - 1.75, ops_ascl_best / 1000.0 * 0.4,
         f"{pct_of_turbo:.0f}% of Turbo cost", color=C_ASCL, fontsize=9,
         fontweight="bold", ha="center",
         bbox=dict(facecolor="w", edgecolor=C_ASCL, boxstyle="square,pad=0.3"))

ax2.set_xlabel(r"$E_b/N_0$ (dB)", fontsize=11)
ax2.set_ylabel("Effective Operations per Frame ($\\times 10^3$)", fontsize=11)
ax2.set_xlim(x0, x1 + 1.5)
ax2.set_ylim(0, max(ops_conv, ops_ascl.max()) / 1000.0 * 1.1)
ax2.grid(True, color="0.85", linewidth=0.6)
ax2.set_axisbelow(True)
ax2.tick_params(labelsize=10)
ax2.legend(["Conv (fixed)", "Turbo (fixed)", "LDPC (fixed)",
            "Polar-Fix (fixed)", "ASCL (adaptive)"],
           loc="upper right", fontsize=8)

fig.tight_layout(pad=0.7)

pdf = os.path.join(OUT, "awgn_5fec_complexity_v2.pdf")
fig.savefig(pdf)
fig.savefig(os.path.join(OUT, "awgn_5fec_complexity_v2.png"), dpi=200)
plt.close(fig)
print("saved:", pdf)
print("ASCL: %.0f ops at low SNR (p=%.2f) -> %d at high SNR (p=%.4f), %.0f%% of turbo"
      % (ops_ascl[0], p_expand[0], ops_ascl_best, p_expand[-1], pct_of_turbo))
