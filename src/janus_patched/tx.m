%+------------------------------------------------------------------------+
%| JANUS is a simple, robust, open standard signalling method for         |
%| underwater communications. See <http://www.januswiki.org> for details. |
%+------------------------------------------------------------------------+
%| Example software implementations provided by STO CMRE are subject to   |
%| Copyright (C) 2008-2018 STO Centre for Maritime Research and           |
%| Experimentation (CMRE)                                                 |
%|                                                                        |
%| This is free software: you can redistribute it and/or modify it        |
%| under the terms of the GNU General Public License version 3 as         |
%| published by the Free Software Foundation.                             |
%|                                                                        |
%| This program is distributed in the hope that it will be useful, but    |
%| WITHOUT ANY WARRANTY; without even the implied warranty of FITNESS     |
%| FOR A PARTICULAR PURPOSE. See the GNU General Public License for       |
%| more details.                                                          |
%|                                                                        |
%| You should have received a copy of the GNU General Public License      |
%| along with this program. If not, see <http://www.gnu.org/licenses/>.   |
%+------------------------------------------------------------------------+
%| Authors: Ricardo Martins, Unknown                                      |
%+------------------------------------------------------------------------+
%
% TX Generate a JANUS waveform.
%
% Inputs:
%    pset       Parameter set structure, created by PSET_NEW or PSET_LOAD.
%    fs         Sampling frequency (Hz).
%    params     Optional parameters.
%
% Outputs:
%    bband      JANUS waveform.
%    pkt        Encoded packet structure.
%    state      Structure with info from the decoder.
%
% See also parameters, stream_new, pset_new, pset_load.
%

function [bband, pkt, state] = tx(pset, bband_fs, params)

    global verbose;

    defaults;

    tx_path = fileparts(mfilename('fullpath'));
    addpath([tx_path '/plugins']);

    if (nargin < 3)
        params = parameters({});
    end

    verbose = params.verbose;

    %% Initialize output variables.
    bband = [];
    state = {};
    state.pset_id = pset.id;
    state.pset_name = pset.name;
    state.cfreq = pset.cfreq;
    state.bwidth = pset.bwidth;
    state.chip_frq = pset.chip_frq;
    state.chip_dur = pset.chip_dur;
    state.prim_q = pset.prim_q;
    state.prim_a = pset.prim_a;
    state.nblock = pset.nblock;

    bband_ts = 1 / bband_fs;

    % Vector with "chip time" values.
    chip_time = 0 : bband_ts : round(pset.chip_dur / bband_ts) * bband_ts;
    chip_time = chip_time(:);

    % Number of samples in a chip.
    chip_nsample = length(chip_time);

    % Optional: Wake-up tones.
    if (params.wut)
        wut = wake_up_tones(bband_ts, chip_nsample * NCHIP_WUT, pset.bwidth);
        wut_gap = zeros(fix(WUT_GAP * bband_fs), 1);
    else
        wut = [];
        wut_gap = [];
    end

    % 32-chip acquisition sequence.
    a32c = params.c32_sequence;
    a32c_nbits = length(a32c);

    % Encode and interleave packet.
    pkt = packet_new(params, pset.id);
    [pkt_bits, crg_bits, pkt] = packet_pack(pkt);
    pkt_nbits = length(pkt_bits);
    [pkt_coded, state.pkt_fec] = fec_encode_bits(pkt_bits, params);
    pkt_nchip = length(pkt_coded);

    % Encode and interleave optional cargo.
    crg_nbits = length(crg_bits);
    crg_coded = [];
    crg_nchip = 0;
    if (crg_nbits > 0)
        [crg_coded, state.crg_fec] = fec_encode_bits(crg_bits, params);
        crg_nchip = length(crg_coded);
    else
        state.crg_fec = [];
    end

    nchip = a32c_nbits + pkt_nchip + crg_nchip;
    coded = [a32c, pkt_coded, crg_coded];

    % Generate hopping pattern. Determines the frequency block position over time
    % "dummy" holds the block number for each symbol First column of slots holds
    % block id, second holds slot id.
    slots = zeros(nchip, 2);
    slots(:, 1) = hop_pattern(pset.prim_a, pset.prim_q, nchip);
    slots(:, 2) = coded' + 1;

    % Build the FH-BFSK chip sequence.
    dum = hamming(fix(chip_nsample / 8));
    dum = dum(1 : fix(chip_nsample / 16));
    ld = length(dum);
    win = [dum' ones(1, chip_nsample - 2 * ld) fliplr(dum')]';

    fh = (fix(CHIP_NFRQ / 2) * ALPHABET_SIZE + 1) * pset.chip_frq;
    bband = zeros((ceil(nchip  * pset.chip_dur * bband_fs + 1)), 1);
    
    count1 = 1;
    for kt = 1 : nchip
        lchip = round(kt * pset.chip_dur * bband_fs) - round((kt - 1) * pset.chip_dur * bband_fs);
        count2 = count1 + lchip - 1;
        % Bottom edge of a block.
        fblock = - fh + slots(kt, 1) * ALPHABET_SIZE * pset.chip_frq;
        % Frequency of a slot in the block.
        f0 = fblock + (slots(kt, 2) - 1) * pset.chip_frq;
        % Waveform of the single chip.
        a = win(1 : lchip) .* exp(1i * 2 * pi * f0 * chip_time(1 : lchip));
        % Append each chip to form the digital signal.
        bband(count1 : count2) = bband(count1 : count2) + a;
        count1 = count2 + 1;
    end

    % Padding.
    if (params.pad)
        pad = zeros(PAD_NCHIP * chip_nsample, 1);
    else
        pad = [];
    end

    % Assemble everything.
    bband = [pad; wut; wut_gap; bband; pad];

    % Coded symbols.
    state.coded_symbols = coded(33 : end)';
    state.fec_mode = params.fec_mode;
end
