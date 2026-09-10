# Simulation chain

What the code actually does, end to end, and where each piece lives.

## The signal path

```
   64 information bits
        |
        v
   FEC encoder                       src/fec/*_encode_*.m
        |  144 coded bits
        v
   prime block interleaver           interleave.m / interleaver_prime.m (upstream, unchanged)
        |
        v
   FH-BFSK modulator                 src/phy/fhbfsk_mod.m
        |  complex baseband @ 44.1 kHz
        v
   channel                           AWGN, or 3-tap Rician + AWGN
        |
        v
   noncoherent energy detector       src/phy/fhbfsk_demod.m
        |  P(bit=1) per chip
        v
   deinterleaver                     deinterleave.m (upstream, unchanged)
        |
        v
   FEC decoder                       src/fec/*_decode_*.m
        |
        v
   64 decoded bits -> BLER / BER
```

The invariant that makes the comparison fair: **only the first and last blocks
change between codes.** The interleaver, modulator, channel, and detector are
byte-identical across all five runs, so a BLER difference cannot come from the
front end.

## FH-BFSK modulation — `src/phy/fhbfsk_mod.m`

Extracted from the janus-m `tx.m` chip loop so it can be driven directly by a
campaign script, without the acquisition sequence, wake-up tones, or padding that
a full JANUS packet carries. What it preserves from the standard:

- The 4160 Hz band centered at 11,520 Hz, divided into 13 frequency blocks of two
  tone slots each, 160 Hz per slot.
- The Galois-field hopping pattern from `hop_pattern(pset.prim_a, pset.prim_q, ·)`
  — unchanged upstream code, so the hop sequence is the standard one.
- Chip duration 6.25 ms = 1/160 Hz, and the Hamming-tapered chip window built the
  same way `tx.m` builds it (`hamming(chip_nsample/8)` truncated to the first
  1/16 and mirrored).

Each chip is a windowed complex sinusoid at `f0 = fblock + bit * chip_frq`, where
`fblock` comes from the hop pattern and `bit` selects one of the block's two tones.

Under a frequency-flat channel every tone sees the same SNR, so the hopping buys
nothing. It only pays off under frequency selectivity — which is precisely what
the three-tap campaign tests, and why the hopping pattern had to stay authentic
rather than be abstracted away.

## Noncoherent energy detection — `src/phy/fhbfsk_demod.m`

Extracted from `demod.m` plus `fsk2prob.m`. Per chip, the receiver correlates the
received samples against the two candidate tone templates of the active block and
takes the squared magnitude — the energy, with the carrier phase discarded:

```
E(k,b) = | sum_n r[n] w[n] exp(-j2*pi*f(k,b)*n/fs) |^2 / M_k^2 ,   b in {0,1}
```

Templates use a Tukey window (`tukeywin(·, 0.05)`) and are built once for all
`prim_q * 2` possible tone frequencies, then indexed by the hop pattern —
the same pattern the modulator used, recomputed independently on the receive side.

The two energies become a soft metric by normalized difference:

```
P(bit=1) = ((E1 - E0) / (E0 + E1) + 1) / 2
```

which lands in (0,1). This is the same mapping `fsk2prob.m` applies in the stock
receiver, so the soft-metric quality the decoders see is the quality a real JANUS
receiver would hand them.

**This is the crux of the paper.** It is a *linear* approximation to the optimal
noncoherent LLR (which involves modified Bessel functions), and it collapses the
two-dimensional I/Q observation to one scalar per tone. The resulting soft metrics
are coarser than coherent detection would produce, which is why the coding gains
of turbo and polar compress to 0.2–0.3 dB instead of the ~1 dB that coherent
studies report.

## Feeding the decoders

Decoders disagree on what a soft input is, so the conversion happens per code:

| Code | Input | Conversion |
|---|---|---|
| Conv (Viterbi) | 8-bit soft-decision levels | `round(P * 255)`, then `vitdec(..., 'soft', 8)` |
| Turbo, LDPC, Polar | LLR | `log((1 - P) / P)` |

Note the LLR convention in this codebase is **log(P0/P1)**, not the more common
log(P1/P0). The Communications Toolbox turbo and LDPC decoders expect the opposite
sign, so `turbo_decode_janus` and `ldpc_decode_janus` flip it internally. The
campaign script does not assume this — it detects the correct polarity empirically
before the sweep by decoding a noiseless frame both ways, and prints the outcome
(`Turbo LLR sign: FLIPPED`, `LDPC LLR sign: normal`). Sign errors here produce
plausible-looking-but-wrong curves, which is why the check is a hard gate rather
than a comment.

## Two integration paths

The five codes reach the waveform by two different routes, which is worth knowing
before reading the code:

**Conv and Polar go through the JANUS chain.** `fec_encode_bits` and
`fec_decode_soft_bits` are the pluggable FEC layer that `tx.m` and `rx.m` call,
dispatching on `params.fec_mode` (`FEC_MODE_CONV`, `FEC_MODE_POLAR`). Interleaving
and deinterleaving happen inside the dispatcher. This is the path a real modified
JANUS node would take.

**Turbo and LDPC are standalone codecs.** `turbo_encode_janus` / `ldpc_encode_janus`
and their decoders are called directly by the campaign script, which applies the
same `interleave`/`deinterleave` calls explicitly around them. They were added for
the comparison and never wired into `parameters.m` as FEC modes.

The two routes apply the identical interleaver to the identical coded length, so
the comparison holds — but if you extend this work, the dispatcher is the path to
extend, and turbo/LDPC are the ones to fold in.

## Rate matching to E = 144

The JANUS minimum packet fixes the coded length at 144 chips. Each code reaches it
differently, and the differences are not cosmetic:

- **Conv** — 64 bits + 8 tail bits = 72, times rate 1/2 = 144 exactly. The tail
  costs 11 % of the rate, so the effective rate is 64/144 = 0.444, not 1/2.
- **Turbo** — a rate-1/3 mother code produces 204 bits, punctured to 144 with an
  LTE-style pattern.
- **LDPC** — the (144,64) PEG matrix is constructed natively at the target length,
  so no rate matching is needed. `build_ldpc_matrix_144_64.m` builds it with
  column weight 3, mean row weight 5.4, and guaranteed girth ≥ 6, and verifies the
  80×144 matrix has full rank 80.
- **Polar** — an N = 128 mother code with CRC-11 (information set size 75) is
  extended to 144 by circular-repetition rate matching per 3GPP TS 38.212. The
  reliability order comes from the Gaussian approximation at a 2.0 dB design point,
  with list size L = 8 and CRC-11 — the combination selected by an offline sweep
  over design Eb/N0, list size, and CRC length.

All five therefore transmit exactly 144 chips through the same modulator, and every
code carries its own structural penalty — the tail for Conv, puncturing for turbo,
short cycles for LDPC, repetition for polar. That is the honest version of
"equal conditions" at this block length.

## Adaptive-SCL

`polar_ca_scl_decode_bits.m` implements both the fixed and the adaptive decoder.
Adaptive-SCL starts at list size L₀ = 4; if the CRC-11 check fails on the best
path, it re-decodes at L = 8. The CRC therefore serves two purposes at once —
selecting among list candidates, and deciding whether the cheap pass was good
enough.

`run_ascl_profile_fhbfsk.m` measures the resulting cost by recording, per SNR
point, the average number of decode attempts and the average final list size over
5,000 frames. At low SNR most frames fail at L₀ and the wasted first pass makes
ASCL *more* expensive than fixed-SCL; above 10 dB over 99 % of frames succeed at
L₀ = 4, so the cost converges to L₀·N·log₂N ≈ 3,584 operations.

The saving is structural, not statistical: it comes from the CRC being available
mid-decode, which a fixed-iteration turbo decoder and a single-pass Viterbi
decoder have no way to exploit.

## Channel models

**AWGN** — complex Gaussian noise added at the waveform level, variance set from
the target Eb/N0 given the 44.1 kHz sampling rate and the code rate.

**Three-tap Rician** — `sample_uwa_taps_waveform` builds a sample-level impulse
response from chip-normalized tap delays. Tap 1 is Rician with K = 6 dB (a
deterministic line-of-sight component plus a Gaussian diffuse part); taps 2 and 3
are Rayleigh. Per-frame energy is normalized to unity, and an independent
realization is drawn for every frame, so the reported BLER averages over the
fading distribution rather than over one lucky channel.

With delays [0, 1, 3] ms the rms delay spread is 0.83 ms, putting the coherence
bandwidth near 240 Hz — above the 160 Hz tone spacing but below the 320 Hz block
spacing. The two tones of a pair fade together while separate hopping blocks fade
independently, so the hopping pattern delivers genuine frequency diversity here.

The third tap at 3 ms spans 48 % of the 6.25 ms chip. That inter-chip interference
does not shrink as noise falls, which is what sets the BLER ≈ 4.4 × 10⁻² error
floor shared by Conv, turbo, and polar — an artifact of the front end that no FEC
choice can remove.
