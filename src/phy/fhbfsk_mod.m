function [bband, info] = fhbfsk_mod(coded_bits, pset, bband_fs)
%FHBFSK_MOD  Generate FH-BFSK waveform from coded bits.
%
%   Standalone modulator extracted from tx.m (lines 110-139) for use in
%   waveform-level FEC comparison campaigns.  Does NOT include acquisition
%   sequence, wake-up tones, or padding — only the data chips.
%
%   Inputs:
%     coded_bits  Row vector of coded bits (logical or 0/1), length E.
%     pset        Parameter set structure (from pset_new / pset_load).
%     bband_fs    Baseband sampling frequency (Hz), e.g. 44100.
%
%   Outputs:
%     bband       Complex baseband waveform (column vector).
%     info        Struct with fields:
%                   nchip, chip_nsample, slots, fh, bband_fs

    defaults;

    coded_bits = double(coded_bits(:).');
    nchip = length(coded_bits);

    bband_ts = 1 / bband_fs;

    % Chip time vector & samples per chip
    chip_time = (0 : bband_ts : round(pset.chip_dur / bband_ts) * bband_ts)';
    chip_nsample = length(chip_time);

    % Hamming-tapered window (same as tx.m lines 118-121)
    dum = hamming(fix(chip_nsample / 8));
    dum = dum(1 : fix(chip_nsample / 16));
    ld  = length(dum);
    win = [dum; ones(chip_nsample - 2*ld, 1); flipud(dum)];

    % Hopping pattern: block index per chip
    slots = zeros(nchip, 2);
    slots(:, 1) = hop_pattern(pset.prim_a, pset.prim_q, nchip);
    slots(:, 2) = coded_bits' + 1;   % 1 or 2 (FSK tone index)

    % Frequency offset (center of hopping band)
    fh = (fix(CHIP_NFRQ / 2) * ALPHABET_SIZE + 1) * pset.chip_frq;

    % Build FH-BFSK waveform chip by chip
    bband = zeros(ceil(nchip * pset.chip_dur * bband_fs + 1), 1);
    count1 = 1;
    for kt = 1:nchip
        lchip = round(kt * pset.chip_dur * bband_fs) ...
              - round((kt - 1) * pset.chip_dur * bband_fs);
        count2 = count1 + lchip - 1;

        % Frequency of this chip
        fblock = -fh + slots(kt, 1) * ALPHABET_SIZE * pset.chip_frq;
        f0 = fblock + (slots(kt, 2) - 1) * pset.chip_frq;

        % Windowed complex sinusoid
        a = win(1:lchip) .* exp(1i * 2 * pi * f0 * chip_time(1:lchip));
        bband(count1:count2) = bband(count1:count2) + a;
        count1 = count2 + 1;
    end
    bband = bband(1:count2);  % trim trailing zeros

    % Info
    info.nchip       = nchip;
    info.chip_nsample = chip_nsample;
    info.slots       = slots;
    info.fh          = fh;
    info.bband_fs    = bband_fs;
end
