# Repository contents

Every file in the repository, what it is, and which published result it backs.
47 files total — the repository carries the code and data behind the paper and
nothing else.

Reading order if you are new here: [`METHOD.md`](METHOD.md) for how the
simulation works → [`figure_data_map.md`](figure_data_map.md) for what produced
which result → [`REPRODUCE.md`](REPRODUCE.md) to run it yourself.

**Provenance marks** — `[new]` written for this study · `[mod]` modified from
janus-m 3.0.5 (GPL-3.0, © STO CMRE) · `[gen]` generated output.
See [`../NOTICE.md`](../NOTICE.md) for the licensing consequences.

---

## Root

| File | Description |
|---|---|
| `README.md` | Project overview: the research question, the five codes, headline result tables, quick start, and known limitations. |
| `setup_paths.m` `[new]` | Puts the repository and a local janus-m 3.0.5 tree on the MATLAB path, in the order that makes `src/janus_patched/` shadow the upstream files. Verifies the janus-m root looks valid and reports whether the required toolboxes are licensed. **Run this first, every session.** |
| `NOTICE.md` | Third-party attribution: what came from janus-m, which files were modified and how, and why upstream is not redistributed here. |
| `LICENSE` | GNU GPL v3, inherited from janus-m 3.0.5. |
| `CITATION.cff` | Machine-readable citation metadata; GitHub renders it as a "Cite this repository" button. |
| `.gitignore` | Excludes LaTeX build artifacts, MATLAB autosaves, `__pycache__`, OS metadata, and `.bak` scratch files. |

## `src/` — the simulation chain

### `src/fec/` — FEC layer (13 files)

The encoders and decoders under comparison. All operate at K = 64 information
bits, E = 144 coded bits.

| File | Lines | Description |
|---|---|---|
| `fec_encode_bits.m` `[new]` | 50 | Encoder dispatcher. Switches on `params.fec_mode`, encodes, then applies the JANUS prime block interleaver. Handles `FEC_MODE_CONV` and `FEC_MODE_POLAR`. |
| `fec_decode_soft_bits.m` `[new]` | 73 | Decoder dispatcher and the counterpart to the above. Clips input probabilities away from 0 and 1, deinterleaves, and routes to the right decoder — quantizing to 8-bit soft levels for Viterbi, or converting to LLR as `log(P0/P1)` for polar. |
| `fec_coded_length.m` `[new]` | 37 | Returns the coded length for a given payload size and FEC mode; the hook that keeps every code pinned to E = 144. |
| `polar_ca_encode_bits.m` `[new]` | 119 | CRC-aided polar encoder. Appends CRC-11, places information bits by reliability order, polar-transforms the N = 128 mother code, and rate-matches to 144 by circular repetition (3GPP TS 38.212 style). |
| `polar_ca_scl_decode_bits.m` `[new]` | 286 | Successive cancellation list decoder, **both variants**. Fixed-SCL runs at L = 8; Adaptive-SCL starts at L₀ = 4 and re-decodes at L = 8 only when the CRC fails. Returns decode statistics (attempts, final list size, CRC outcome) used for the complexity profiling. |
| `polar_reliability_order.m` `[new]` | 93 | Bit-channel reliability ranking by Gaussian approximation at a configurable design Eb/N0 (2.0 dB in the published runs). Decides which of the 128 positions carry information and which are frozen. |
| `turbo_make_codec.m` `[new]` | 129 | Builds the turbo encoder/decoder objects and the puncturing mask that takes the rate-1/3 mother codeword from 204 bits down to 144. |
| `turbo_encode_janus.m` `[new]` | 33 | Turbo encode, K = 64 → E = 144, applying that puncturing pattern. |
| `turbo_decode_janus.m` `[new]` | 41 | Turbo decode, max-log-MAP with 6 iterations. Flips LLR sign internally to match the Communications Toolbox convention. |
| `build_ldpc_matrix_144_64.m` `[new]` | 160 | Constructs the (144,64) parity-check matrix by Progressive Edge Growth: column weight 3, girth ≥ 6, no 4-cycles. Verifies the 80×144 result has full rank 80. |
| `ldpc_make_codec.m` `[new]` | 46 | Wraps that matrix into encoder/decoder configuration objects. |
| `ldpc_encode_janus.m` `[new]` | 31 | LDPC encode, K = 64 → E = 144. No rate matching needed — the code is built natively at the target length. |
| `ldpc_decode_janus.m` `[new]` | 45 | LDPC decode, normalized min-sum, up to 50 iterations, with syndrome-based early termination. Also flips LLR sign internally. |

### `src/phy/` — JANUS physical layer (2 files)

Where the paper's central methodological claim lives: the codes are compared over
the real waveform, not a baseband-equivalent stand-in.

| File | Lines | Description |
|---|---|---|
| `fhbfsk_mod.m` `[new]` | 68 | FH-BFSK modulator, extracted from the janus-m `tx.m` chip loop so a campaign script can drive it directly. Preserves the standard's Galois-field hopping pattern, 6.25 ms chip duration, 160 Hz tone spacing, and Hamming-tapered chip window. Emits complex baseband at 44.1 kHz. |
| `fhbfsk_demod.m` `[new]` | 57 | Noncoherent energy detector, extracted from `demod.m` + `fsk2prob.m`. Correlates each chip against the two candidate tones of the active hopping block, squares the magnitudes (discarding carrier phase), and maps the energy pair to `P(bit=1)` by normalized difference. **This is the source of the coding-gain compression the paper reports.** |

### `src/janus_patched/` — modified janus-m files (5 files)

Upstream files, each retaining its CMRE copyright header, changed to route
through the pluggable FEC layer instead of the hard-coded convolutional codec.
These are why the repository is GPL-3.0.

| File | Lines | Change |
|---|---|---|
| `tx.m` `[mod]` | 154 | Calls `fec_encode_bits` instead of the built-in convolutional encoder. |
| `rx.m` `[mod]` | 203 | Calls `fec_decode_soft_bits`; carries FEC configuration through the receive chain. |
| `demod.m` `[mod]` | 101 | Emits per-chip soft metrics for the FEC layer to consume. |
| `parameters.m` `[mod]` | 296 | Adds `fec_mode` plus the polar, turbo, and LDPC configuration fields. |
| `defaults.m` `[mod]` | 75 | Adds the `FEC_MODE_*` constants. |

## `experiments/` — campaign drivers

### Published campaigns (2 files)

Everything in the paper comes from these two scripts.

| File | Lines | Description |
|---|---|---|
| `run_5fec_fhbfsk_campaign.m` `[new]` | 608 | **The main campaign.** Runs all five codes through the FH-BFSK waveform chain under either `'awgn'` or `'uwa'` (three-tap Rician) channel mode. Builds the JANUS parameter set and all five codecs, self-checks before measuring (noiseless round trip, per-decoder LLR polarity, LDPC matrix rank), sweeps Eb/N0 with a 300-frame-error early stop, computes 95 % Wilson intervals and interpolated thresholds, and writes the result `.mat` plus a LaTeX coding-gain table. Produces the data behind **Fig. 1, Fig. 3, Table II, Table IV**. |
| `run_ascl_profile_fhbfsk.m` `[new]` | 221 | Runs Polar Adaptive-SCL alone over FH-BFSK AWGN, recording average decode attempts and average final list size per SNR point over 5,000 frames. Produces the data behind **Fig. 2 and Table III**. |

### `experiments/logs/`

| File | Description |
|---|---|
| `uwa_run_log.txt` `[gen]` | Verbatim console log of the published UWA campaign run: the configuration banner, the LDPC construction and sanity-check results, and per-SNR BLER/BER for all five codes as they were measured. Local paths were replaced with `<repo>` placeholders. Useful as an audit trail — the numbers in Table IV can be read straight out of it. |

## `analysis/` — figure generation (3 files)

All three are matplotlib, and all three force TrueType (Type 42) fonts, which is
what IEEE PDF eXpress requires — matplotlib's default is Type 3, and it is
rejected. Each writes a vector PDF and a 200 dpi PNG into `figures/`.

| File | Lines | Plots |
|---|---|---|
| `make_fig1_awgn.py` `[new]` | 69 | **Fig. 1** — AWGN five-FEC BLER over 5–12 dB. No confidence band: every AWGN point carries 300 frame errors, so the Wilson interval is narrower than the line. |
| `make_fig2_complexity.py` `[new]` | 116 | **Fig. 2** — two panels: analytic operations per frame for all five decoders as a bar chart, and effective operations vs. Eb/N0 with the four fixed-cost decoders as horizontal lines and Adaptive-SCL as a curve that falls with SNR. Shades the ASCL saving relative to turbo. |
| `make_fig3_uwa.py` `[new]` | 64 | **Fig. 3** — UWA five-FEC BLER, with the Wilson band shaded: the UWA tail runs out of frame errors and the interval opens up. |

## `data/`

All files are small (≤ 12 KB); the repository carries the complete result set,
not a sample.

### Paper data (3 files)

| File | Feeds | Description |
|---|---|---|
| `fhbfsk_awgn/fhbfsk_5fec_results.mat` `[gen]` | Fig. 1, Table II | AWGN campaign results: `bler`, `ber`, `nframes`, `nerr_frame`, `nerr_bit` (all 5×25), `ci.lower`/`ci.upper` (95 % Wilson), `gains`, `mode_names`, and `fhbfsk_cfg` — the full configuration of the run, which is the authoritative reproduction record. Eb/N0 0:0.5:12 dB. |
| `fhbfsk_uwa/fhbfsk_5fec_results.mat` `[gen]` | Fig. 3, Table IV | Same structure, three-tap Rician channel, Eb/N0 8:0.5:20 dB, 300 frame errors at every point. |
| `fhbfsk_awgn/ascl_profile.mat` `[gen]` | Fig. 2, Table III | Adaptive-SCL profile: `ebn0_db` (5:0.5:12), `avg_attempts`, `avg_list_size`, `bler`, `L` = 8, `L0` = 4, 5,000 frames per point. |

### `data/tables/` (2 files)

| File | Description |
|---|---|
| `fhbfsk_awgn_5fec_coding_gain.tex` `[gen]` | AWGN coding-gain table: Eb/N0 at BLER 10⁻¹ and 10⁻², and the maximum gain over the Conv baseline. Paper Table II is this with relabeled rows and an added interpolation note. Its header banner names an earlier helper script that re-emitted the table; re-running the AWGN campaign regenerates the same file. |
| `fhbfsk_uwa_5fec_coding_gain.tex` `[gen]` | UWA coding-gain table, emitted by `run_5fec_fhbfsk_campaign.m`. Paper Table IV is this plus the pooled error-floor column. |

## `figures/` (6 files)

The three published figures exactly as submitted: a vector PDF, which is what the
paper includes, plus a PNG companion for display. See
[`figure_data_map.md`](figure_data_map.md) for how closely each one is
reproducible from `data/` via `analysis/`.

| File | Figure |
|---|---|
| `fhbfsk_awgn_5fec_bler_ci_12dB.pdf` / `.png` `[gen]` | Fig. 1 — AWGN BLER |
| `awgn_5fec_complexity_v2.pdf` / `.png` `[gen]` | Fig. 2 — decoding complexity |
| `fhbfsk_uwa_5fec_bler_ci.pdf` / `.png` `[gen]` | Fig. 3 — UWA BLER |

## `docs/` (4 files)

| File | Description |
|---|---|
| `METHOD.md` | The simulation chain end to end: the signal path, what `fhbfsk_mod`/`fhbfsk_demod` preserve from the standard, the soft-metric derivation and why it drives the central result, how each code reaches E = 144 and what structural penalty it pays, the Adaptive-SCL mechanism, and both channel models. |
| `REPRODUCE.md` | The three published runs as copy-pasteable configurations, transcribed from the `fhbfsk_cfg` structs in the result files. Includes the chip-unit tap-delay pitfall, runtime expectations, and the sanity checks each campaign performs before measuring. |
| `figure_data_map.md` | Figure and table provenance, the variable-by-variable contents of each result file, and the audit trail for the UWA run. |
| `CONTENTS.md` | This file. |

---

## Not included, deliberately

| Item | Reason |
|---|---|
| janus-m 3.0.5 upstream tree | Not ours to redistribute; `setup_paths.m` links a local copy. See [`../NOTICE.md`](../NOTICE.md). |
| The manuscript and its LaTeX sources | Published through IEEE. This repository is the code-and-data artifact behind the paper, not a copy of the paper. See [`../CITATION.cff`](../CITATION.cff). |
| NATO/CMRE workshop material, vendor specifications, other authors' papers | Third-party documents consulted during the work, not ours to redistribute. |
| LaTeX build artifacts, `.bak` files, development worklogs, editor and OS metadata | Noise. Covered by `.gitignore`. |
