# Reproducing the published results

Every number in the paper comes from three campaign runs. The exact configuration
of each run is stored **inside** the result `.mat` files (`fhbfsk_cfg` struct), so
the recipes below are transcriptions of what actually ran, not reconstructions.

## Prerequisites

| Requirement | Version used |
|---|---|
| MATLAB | R2023b or later |
| Communications Toolbox | required (Viterbi, turbo, LDPC, polar primitives) |
| Signal Processing Toolbox | required |
| janus-m | 3.0.5 (not redistributed — see [`../NOTICE.md`](../NOTICE.md)) |
| Python (all three figures) | 3.10+ with `numpy`, `scipy`, `matplotlib` |

```matlab
cd <repo root>
setup_paths('C:\path\to\janus-m-3.0.5')
```

`setup_paths` adds the upstream tree first, then layers `src/janus_patched`,
`src/phy`, and `src/fec` on top, and calls `clear functions; rehash` so MATLAB
drops cached copies of the shadowed upstream files. If you edit anything under
`src/`, run `clear functions; rehash` again before the next run.

---

## Run 1 — AWGN campaign (Fig. 1, Table II)

```matlab
cfg = struct();
cfg.channel_mode   = 'awgn';
cfg.K              = 64;
cfg.E              = 144;
cfg.bband_fs       = 44100;
cfg.ebn0_db        = 0:0.5:12;     % 25 points
cfg.max_frames     = 10000;
cfg.min_frame_errors = 300;        % early stop per point
cfg.rng_seed_base  = 42;
cfg.fec_polar_list_len          = 8;
cfg.fec_polar_crc_len           = 11;
cfg.fec_polar_reliability_method = 'ga';
cfg.fec_polar_design_ebn0_db    = 2.0;
cfg.fec_polar_adaptive_min_list = 4;   % L0
out = run_5fec_fhbfsk_campaign(cfg);
```

Writes `data/fhbfsk_awgn/fhbfsk_5fec_results.mat` and the coding-gain table
`fhbfsk_awgn_5fec_coding_gain.tex`.

These are the defaults, so `run_5fec_fhbfsk_campaign()` with no arguments
reproduces this run.

## Run 2 — Three-tap Rician campaign (Fig. 3, Table IV)

> **Do not rely on the defaults for this one.** `uwa_tap_delays` is expressed in
> **chip units** in the waveform-level script, and its default `[0 1 3]` means
> 0/1/3 *chips* — a leftover from the earlier symbol-domain campaign. The paper's
> channel is delays [0, 1, 3] **ms** at 6.25 ms/chip, i.e. `[0 0.16 0.48]` chips.
> The default also enables impulsive noise, which the published run did not use.

```matlab
cfg = struct();
cfg.channel_mode   = 'uwa';
cfg.K              = 64;
cfg.E              = 144;
cfg.bband_fs       = 44100;
cfg.ebn0_db        = 8:0.5:20;          % 25 points
cfg.max_frames     = 10000;
cfg.min_frame_errors = 300;             % reached at every point
cfg.rng_seed_base  = 42;
cfg.uwa_tap_delays   = [0 0.16 0.48];   % chips = [0 1 3] ms at 6.25 ms/chip
cfg.uwa_tap_gains_db = [0 -6 -10];
cfg.uwa_fading       = 'rician';
cfg.uwa_k_factor_db  = 6;
cfg.uwa_normalize_frame_power = 1;      % per-frame channel energy normalized to 1
cfg.uwa_impulsive_prob = 0;             % impulsive noise disabled
cfg.fec_polar_list_len          = 8;
cfg.fec_polar_crc_len           = 11;
cfg.fec_polar_reliability_method = 'ga';
cfg.fec_polar_design_ebn0_db    = 2.0;
cfg.fec_polar_adaptive_min_list = 4;
out = run_5fec_fhbfsk_campaign(cfg);
```

Writes `data/fhbfsk_uwa/fhbfsk_5fec_results.mat` and
`fhbfsk_uwa_5fec_coding_gain.tex`. An independent channel realization is drawn per
frame. The console log of the published run is kept verbatim at
[`../experiments/logs/uwa_run_log.txt`](../experiments/logs/uwa_run_log.txt).

## Run 3 — Adaptive-SCL cost profile (Fig. 2, Table III)

```matlab
cfg = struct();
cfg.ebn0_db    = 5:0.5:12;
cfg.max_frames = 5000;
cfg.fec_polar_list_len          = 8;    % L
cfg.fec_polar_adaptive_min_list = 4;    % L0
cfg.fec_polar_crc_len           = 11;
cfg.fec_polar_design_ebn0_db    = 2.0;
cfg.rng_seed  = 42;
out = run_ascl_profile_fhbfsk(cfg);
```

Runs only Polar Adaptive-SCL through the FH-BFSK chain and records average decode
attempts and average final list size per SNR point. Writes
`data/fhbfsk_awgn/ascl_profile.mat`. These are also the function's defaults.

---

## Figures

All three read the campaign output in `data/` and write a vector PDF plus a
200 dpi PNG into `figures/`. No MATLAB needed for this step.

```bash
python analysis/make_fig1_awgn.py        # Fig. 1 -> figures/fhbfsk_awgn_5fec_bler_ci_12dB.{pdf,png}
python analysis/make_fig2_complexity.py  # Fig. 2 -> figures/awgn_5fec_complexity_v2.{pdf,png}
python analysis/make_fig3_uwa.py         # Fig. 3 -> figures/fhbfsk_uwa_5fec_bler_ci.{pdf,png}
```

Each sets `pdf.fonttype = 42`, because matplotlib defaults to Type 3 fonts and
IEEE PDF eXpress rejects them.

The PDFs already in `figures/` are the versions submitted with the paper. Fig. 3
regenerates byte for byte; Fig. 1 and Fig. 2 match visually but not byte for
byte, because the submitted copies were passed through Ghostscript
(`-dNoOutputFonts`) to convert their text to vector outlines. See
[`figure_data_map.md`](figure_data_map.md).

## Runtime notes

The waveform-level chain is the expensive part: every frame is modulated to
44.1 kHz baseband, passed through the channel, and detected chip by chip. Expect
hours per campaign on a desktop CPU, dominated by the low-SNR points where the
300-error early stop does not trigger before the 10,000-frame cap. The AWGN and
UWA campaigns are independent and can run in separate MATLAB sessions.

`rng_seed_base = 42` makes runs repeatable; the seed is re-derived per SNR point,
so a partial re-run of one point reproduces that point exactly.

## Sanity checks the campaign performs before measuring

The campaign scripts self-check before the sweep, and print the outcome:

1. **Noiseless FH-BFSK round trip** — modulate/detect with no channel, verify the
   coded bits come back intact (10 trials).
2. **LLR polarity per decoder** — the turbo and LDPC decoders in the
   Communications Toolbox disagree on LLR sign convention. The script detects the
   convention and reports `FLIPPED` or `normal`, which is why turbo's line in the
   log reads `Turbo LLR sign: FLIPPED`.
3. **LDPC matrix rank** — confirms the constructed (144,64) PEG matrix has full
   rank 80 with mean row weight 5.4 and column weight 3.0.

If any of these fail, the BLER numbers are meaningless — check them first when
a re-run disagrees with the published curves.
