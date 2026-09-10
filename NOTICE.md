# Third-party code and licensing

## janus-m 3.0.5 (STO CMRE) — GPL-3.0

This work is a **patch on top of** the JANUS reference MATLAB implementation
`janus-m 3.0.5`, © 2008–2018 STO Centre for Maritime Research and Experimentation
(CMRE), released under the GNU General Public License version 3.

The upstream tree is **not redistributed here**. Obtain it from the official
JANUS distribution (<https://www.januswiki.org>) and point `setup_paths.m` at it:

```matlab
setup_paths('C:\path\to\janus-m-3.0.5')
```

`setup_paths.m` adds the upstream tree to the MATLAB path first, then adds
`src/janus_patched`, `src/phy`, and `src/fec` on top so that the modified files
shadow their upstream counterparts.

Because this repository contains modified GPL-3.0 files and original files that
link against them, the whole repository is distributed under **GPL-3.0**
(see `LICENSE`).

## File-by-file provenance

### Modified upstream files — `src/janus_patched/`

Derived from janus-m 3.0.5. Each retains its original CMRE copyright header.
Modified to route encoding/decoding through the pluggable FEC layer instead of the
hard-coded convolutional codec.

| File | Change |
|---|---|
| `tx.m` | Calls `fec_encode_bits` instead of the built-in convolutional encoder |
| `rx.m` | Calls `fec_decode_soft_bits`; carries FEC configuration through the chain |
| `demod.m` | Emits per-chip soft metrics for the FEC layer |
| `parameters.m` | Adds `fec_mode` and the polar/turbo/LDPC configuration fields |
| `defaults.m` | Adds the `FEC_MODE_*` constants |

### Original files — `src/fec/`, `src/phy/`, `experiments/`, `analysis/`

Written for this study. `fec_coded_length.m` retains the upstream header block
because it replaces an upstream function of the same role.

- `src/fec/` — FEC dispatcher plus the polar (CA-SCL and Adaptive-SCL), turbo,
  and LDPC encoders, decoders, and codec builders, including the (144,64) PEG
  parity-check matrix construction.
- `src/phy/` — `fhbfsk_mod.m` and `fhbfsk_demod.m`: the FH-BFSK waveform generator
  and the noncoherent energy detector used for the waveform-level simulation.
- `experiments/` — campaign drivers.
- `analysis/` — figure generation.

## Other third-party material

Third-party reference documents consulted during the work (NATO/CMRE JANUS
workshop material, vendor specifications, and other authors' papers) are
deliberately **not** included in this repository, as they are not ours to
redistribute. Neither is the manuscript itself, which is published through IEEE.
