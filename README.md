# Short-Block FEC Comparison for the JANUS Underwater Acoustic Standard

Waveform-faithful comparison of five forward error correction (FEC) codes at the
JANUS (STANAG 4748) minimum packet operating point — **K = 64 information bits,
E = 144 coded bits, R ≈ 0.444** — simulated over **actual FH-BFSK waveforms with
noncoherent energy detection** rather than a coherent baseband-equivalent model.

> **Paper:** H. Lee, S. Kim, S. Park, J. Hong, and T. Im, *"Comparative Analysis of
> Short-Block FEC Codes for the JANUS Underwater Communication Standard,"*
> accepted to OCEANS 2026 Monterey.
> Dept. of Information and Communication Eng., Hoseo University.
>
> This repository is the code and data behind that paper — the simulation chain,
> the campaign results, and every published figure and table built from them. The
> manuscript is published through IEEE and is not redistributed here.

---

## Why this is not just another FEC benchmark

Published short-block FEC comparisons almost always run over a coherent
baseband-equivalent channel. JANUS does not: it transmits frequency-hopped BFSK
and detects it **noncoherently**, discarding carrier phase. This repository keeps
the real JANUS physical layer in the loop — FH-BFSK modulation, the Galois-field
hopping pattern, chip timing, and the standard prime-based block interleaver —
and swaps **only** the FEC block. Every code therefore sees an identical front end,
so any difference is attributable to the code itself.

The result is a finding a coherent model cannot produce: **noncoherent detection
compresses coding-gain differences**, which moves the design decision from block
error rate to decoding complexity.

## The five codes

All configured at K = 64, E = 144:

| FEC | Encoder | Decoder | Short-block note |
|---|---|---|---|
| Conv (JANUS legacy) | CL 9, R = 1/2, `[753,561]` octal | soft Viterbi, TD = 45 | 11 % tail overhead |
| Turbo | CL 4, `[13,15]` octal, S-random interleaver | max-log-MAP × 6 | limited interleaver spreading |
| LDPC | PEG, d_v = 3, (144,64), girth ≥ 6 | normalized min-sum × 50 | short-cycle BP convergence |
| Polar-Fix | N = 128, CRC-11, Gaussian approx. | SCL, L = 8 | near-ML performance |
| Polar-Adp | N = 128, CRC-11, Gaussian approx. | Adaptive-SCL, L₀ = 4 → 8 | adaptive complexity |

## Headline results

**AWGN, FH-BFSK, noncoherent** — Eb/N0 (dB) to reach the target BLER, and gain over Conv:

| FEC | @ 10⁻¹ | @ 10⁻² | G_max |
|---|---|---|---|
| Conv | 8.8 | 9.7 | 0.0 |
| Turbo | 8.8 | 9.5 | **+0.3** |
| LDPC | 9.7 | 10.9 | −1.0 |
| Polar-Fix | 8.7 | 9.5 | +0.2 |
| Polar-Adp | 8.7 | 9.5 | +0.2 |

**Three-tap Rician (frequency-selective)** — the compression becomes complete:

| FEC | @ 2×10⁻¹ | @ 10⁻¹ | G | Error floor |
|---|---|---|---|---|
| Conv | 11.84 | 14.09 | 0.00 | 0.044 |
| Turbo | 12.14 | 14.03 | +0.06 | 0.044 |
| LDPC | 14.29 | 16.83 | **−2.74** | 0.083 |
| Polar-Fix | 12.12 | 14.15 | −0.06 | 0.044 |
| Polar-Adp | 12.13 | 14.11 | −0.02 | 0.044 |

**Per-frame decoding complexity** — the actual differentiator:

| Decoder | Order | Ops/frame | Adaptivity |
|---|---|---|---|
| Conv (Viterbi) | 2^(ν−1)·E | 36,864 | fixed |
| Turbo (MAP × 6) | 2I·2^ν_T·K | 6,144 | fixed |
| LDPC (NMS × 50) | I·d_v·E | 21,600 | early stop |
| Polar-Fix (SCL) | L·N·log N | 7,168 | fixed |
| Polar-Adp (ASCL) | L₀·N·log N | **3,584**–10,752 | CRC-adaptive |

Three takeaways:

1. **Coding gain compresses under noncoherent detection.** Turbo and polar buy only
   0.2–0.3 dB over the legacy convolutional code at BLER 10⁻², and under
   frequency-selective fading the gap closes to within 0.06 dB — the 95 % confidence
   intervals of Conv, turbo, and polar overlap at every simulated point above 8 dB.
2. **Adaptive-SCL wins on cost, not on BLER.** CRC-aided early termination drives
   per-frame cost to ~3,584 operations at high SNR — 58 % of turbo's fixed budget —
   while matching turbo's BLER to within 0.1 dB at BLER 10⁻².
3. **The real bottleneck is the front end.** Conv, turbo, and polar share an error
   floor at BLER ≈ 4.4 × 10⁻², set by residual inter-chip interference from the
   3 ms channel tap that spans 48 % of the 6.25 ms chip. No choice of FEC removes it;
   receiver-side equalization is required.

## Repository layout

```
src/fec/            FEC encode/decode layer (polar CA-SCL/ASCL, turbo, LDPC, dispatcher)
src/phy/            FH-BFSK modulator + noncoherent energy detector
src/janus_patched/  janus-m files modified to route through the FEC layer
experiments/        Simulation campaign drivers
  run_5fec_fhbfsk_campaign.m   main campaign (AWGN + UWA) — Fig. 1 & 3 data
  run_ascl_profile_fhbfsk.m    Adaptive-SCL profiling — Fig. 2 data
  logs/             raw console log of the UWA campaign run
analysis/           Figure generation (matplotlib) — one script per figure
data/               Campaign result .mat files and auto-generated LaTeX tables
figures/            Vector figures as they appear in the paper
docs/
  CONTENTS.md       every file in the repository, described
  METHOD.md         the simulation chain end to end — waveform, detector, rate matching
  REPRODUCE.md      exact configuration of every published run
  figure_data_map.md   which script and which .mat produced each figure and table
```

Every file in the repository backs a published figure, table, or number. A
file-by-file walkthrough of all 47 — what each script does and which result it
produces — is in [`docs/CONTENTS.md`](docs/CONTENTS.md).

## Quick start

Requires MATLAB (Communications Toolbox + Signal Processing Toolbox) and the
**janus-m 3.0.5** reference implementation, which is *not* redistributed here —
see [`NOTICE.md`](NOTICE.md) for why, and where to get it.

```matlab
setup_paths('C:\path\to\janus-m-3.0.5')   % layers this patch on top of upstream

% Fig. 1 + Table II — AWGN, 0:0.5:12 dB, up to 10,000 frames/point
cfg = struct('channel_mode', 'awgn');
out = run_5fec_fhbfsk_campaign(cfg);

% Fig. 3 + Table IV — three-tap Rician, 8:0.5:20 dB, 300 frame errors/point
cfg = struct('channel_mode', 'uwa');
out = run_5fec_fhbfsk_campaign(cfg);

% Fig. 2 + Table III — Adaptive-SCL cost profile
out = run_ascl_profile_fhbfsk();
```

Then regenerate the figures — all three are matplotlib, no MATLAB needed:

```bash
python analysis/make_fig1_awgn.py        # -> figures/fhbfsk_awgn_5fec_bler_ci_12dB.{pdf,png}
python analysis/make_fig2_complexity.py  # -> figures/awgn_5fec_complexity_v2.{pdf,png}
python analysis/make_fig3_uwa.py         # -> figures/fhbfsk_uwa_5fec_bler_ci.{pdf,png}
```

Full walkthrough, runtimes, and the exact configuration behind every published
number: [`docs/REPRODUCE.md`](docs/REPRODUCE.md). How the chain works —
waveform generation, the noncoherent soft metric, rate matching to E = 144, and
the Adaptive-SCL mechanism: [`docs/METHOD.md`](docs/METHOD.md).

One gotcha worth naming up front: for the UWA campaign, `uwa_tap_delays` is in
**chip units**, and the default `[0 1 3]` is a leftover from an earlier
symbol-domain campaign. The paper's channel is `[0 0.16 0.48]` chips
(= [0, 1, 3] ms at 6.25 ms/chip), with impulsive noise disabled. Pass it
explicitly, as `docs/REPRODUCE.md` does.

## What is in `data/`

| File | Feeds | Contents |
|---|---|---|
| `fhbfsk_awgn/fhbfsk_5fec_results.mat` | Fig. 1, Table II | BLER/BER + 95 % Wilson CI, 5 codes × 25 SNR points |
| `fhbfsk_awgn/ascl_profile.mat` | Fig. 2, Table III | ASCL average attempts and list size vs. Eb/N0 |
| `fhbfsk_uwa/fhbfsk_5fec_results.mat` | Fig. 3, Table IV | Same, over the three-tap Rician channel |
| `tables/*.tex` | Tables II, IV | Auto-generated LaTeX, emitted by the campaign scripts |

Each `.mat` carries the full BLER/BER grid together with its Wilson intervals and
the exact `fhbfsk_cfg` used to produce it, so a figure can be redrawn without
re-running the campaign.

## Statistical practice

Every BLER point carries a 95 % Wilson confidence interval. The AWGN campaign
terminates a point early once 300 frame errors are observed, capped at 10,000
frames; above 9.5 dB (10.5 dB for LDPC) the error count falls below 300 and the
intervals widen accordingly — points with zero observed errors are omitted rather
than plotted at zero. The UWA campaign reaches 300 frame errors at every point, so
all of its estimates carry comparable weight. Thresholds come from linear
interpolation of log₁₀ BLER on the 0.5 dB simulation grid.

Sub-0.1 dB differences in the reported thresholds lie inside that statistical
uncertainty, and the paper reports them as such rather than as real gaps.

## Known limitations

Stated plainly, because they bound what these numbers mean:

- One three-tap delay profile only (rms delay spread 0.83 ms) — sensitivity to
  delay spread is not characterized, and Doppler and impulsive noise are not modeled.
- Complexity is asymptotic operation counts; real throughput on ARM or FPGA targets
  depends on implementation and memory architecture, and may reorder the ranking.
- LDPC is regular PEG (d_v = 3) only; optimized irregular or protograph designs may
  partially close the 1.2 dB gap.
- The energy-ratio soft metric is a linear approximation to the optimal noncoherent
  LLR, which involves modified Bessel functions.
- Perfect chip synchronization is assumed; no measured-channel replay
  (e.g. Watermark) validation yet.

## License and attribution

Code: **GPL-3.0**, inherited from janus-m 3.0.5 (© 2008–2018 STO CMRE).
See [`LICENSE`](LICENSE) and [`NOTICE.md`](NOTICE.md) for the file-by-file
breakdown of what is upstream, what is modified upstream, and what is original.

The figures in `figures/` are generated by the scripts in `analysis/` from the data
in `data/`, and are the authors' own work product. The manuscript is published
through IEEE and is not redistributed here; cite it using [`CITATION.cff`](CITATION.cff).
