function bit_prob = fhbfsk_demod(bband, pset, bband_fs, nchip)
%FHBFSK_DEMOD  Non-coherent FH-BFSK demodulation (energy detection).
%
%   Standalone demodulator extracted from demod.m (lines 56-95) + fsk2prob.
%   Returns soft metrics as P(bit=1) for each chip, suitable for feeding
%   directly to fec_decode_soft_bits or turbo/ldpc decoders via LLR.
%
%   Inputs:
%     bband     Received complex baseband waveform (column vector).
%     pset      Parameter set structure.
%     bband_fs  Baseband sampling frequency (Hz).
%     nchip     Number of coded chips (= E, e.g. 144).
%
%   Outputs:
%     bit_prob  Column vector of P(bit=1), length nchip, range (0,1).

    defaults;

    bband_ts = 1 / bband_fs;

    % Build correlation templates for all possible FSK frequencies
    fh    = (fix(CHIP_NFRQ / 2) * ALPHABET_SIZE + 1) * pset.chip_frq;
    fkeep = -fh + (0 : pset.prim_q * 2 - 1) * pset.chip_frq;

    factor = pset.chip_dur * bband_fs;   % cfactor=1 (no Doppler)
    t  = (0 : bband_ts : ceil(factor - 1) * bband_ts)';
    tw = tukeywin(length(t), 0.05);
    st = tw .* exp(-1i * 2 * pi * fkeep .* t);   % (nsamp x nfreqs)

    % Hopping pattern (must match modulator)
    slots_block = hop_pattern(pset.prim_a, pset.prim_q, nchip);

    % Energy detection per chip
    stats = zeros(ALPHABET_SIZE, nchip);
    grab1 = 1;
    for kk = 1:nchip
        lchip = round(kk * factor) - round((kk - 1) * factor);
        grab2  = grab1 + lchip - 1;

        % Two correlation templates for this block (bit=0, bit=1)
        slots_idx = slots_block(kk) * 2;
        w = st(1:lchip, [slots_idx+1, slots_idx+2]);

        % Non-coherent energy: |correlation|^2
        stats(:, kk) = (abs(bband(grab1:grab2).' * w) / lchip) .^ 2;

        grab1 = grab2 + 1;
    end

    % FSK energy -> probability (same as fsk2prob.m)
    r    = stats';                         % nchip x 2
    sumr = sum(r, 2);
    sumr(sumr == 0) = 1;                   % avoid division by zero
    a1 = r(:,1) ./ sumr;
    b1 = r(:,2) ./ sumr;
    bit_prob = ((b1 - a1) + 1) / 2;       % 0 < p < 1
end
