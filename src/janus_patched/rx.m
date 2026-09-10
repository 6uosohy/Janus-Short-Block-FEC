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
%| Authors: Ricardo Martins, Giovanni Zappa, Luigi Elia D'Amaro           |
%+------------------------------------------------------------------------+
%
% RX Interface to decode a JANUS waveform.
%
% Inputs:
%    pset       Parameter set structure.
%    bband      Complex baseband waveform.
%    bband_fs   Baseband sampling frequency (Hz).
%    params     Optional parameters.
%
% Outputs:
%    pkt        Decoded packet structure.
%    pkt_bytes  Unprocessed packet bytes.
%    state      Structure with info from the decoder.
%
% Remarks:
%    Set global variable verbose different from 0 to plot various
%    debugging informations.

function [pkt, pkt_bytes, state] = rx(pset, bband, bband_fs, params)

    global verbose;

    rx_path = fileparts(mfilename('fullpath'));
    addpath([rx_path '/plugins']);

    defaults;
    
    if (nargin < 3)
        params = parameters();
    end

    verbose = params.verbose;

    %% Initialize output variables to sane values.
    pkt = {};
    pkt_bytes = [];
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
    state.pkt_idx = 0;
    state.crg_idx = 0;
    state.pkt_raw_bits = [];
    state.pkt_dec_bits = [];
    state.crg_raw_bits = [];
    state.crg_dec_bits = [];
    state.fec_mode = params.fec_mode;
    
    % Number of samples in a chip.
    chip_nsample = round(pset.chip_dur * bband_fs);
    
    %% Search 32 chips.
    pkt_nchip = fec_coded_length(PKT_MIN_NBIT, params);
    slots = hop_pattern(pset.prim_a, pset.prim_q, 32 + pkt_nchip);

    % Chip oversampling.
    chip_oversampling = 4;

    % Max Doppler speed.
    if (~params.doppler_correction)
        max_speed = 0;
    else
        max_speed = params.doppler_max_speed;
    end

    [ freq_vec, chip_order ] = detector_parameters(params, pset, slots(1 : 32));
    [ chip_corr, align_delay ] = chips_alignment(bband, bband_fs, pset.chip_dur, chip_oversampling, freq_vec, chip_order, max_speed);
    
    cfar_mov_avg_time = .150;
    cfar_mov_avg = max(cfar_mov_avg_time, 26 * pset.chip_dur);
    step_l = fix(cfar_mov_avg * chip_oversampling / pset.chip_dur);

    guard_time = chip_oversampling * params.pset_chip_len_mul; % one chip

    % Todo: choose the optimal threshold.
    threshold = 2.5;

    d_istart = step_l + guard_time +1;
    d_istop = length(chip_corr);

    if (d_istart >= d_istop)
        error('janus:rx:nosig', 'no signal detected');
    end

    % Detection.
    offs_detector = detect_first(chip_corr, threshold, step_l, chip_oversampling, guard_time);

    % Converting oversampled chip in baseband index and time.
    offs = fix(offs_detector * chip_nsample / chip_oversampling + align_delay * bband_fs);

    state.after = offs / bband_fs;

    if (isempty(offs))
        error('janus:rx:nosig', 'no signal detected');
    end
    
    if (verbose)
        figure(1);
        plot((0 : length(bband) - 1) / bband_fs, real(bband), 'b', ...
             [0 pset.chip_dur] + state.after, [real(bband(offs)) ...
             real(bband(offs + chip_nsample)) ], 'or');
        xlim([-1 2] * pset.chip_dur + state.after);
    end
    
    max_cfactor = 1540 / (1540 - max_speed);
    if (params.doppler_correction)
        [state.gamma, state.speed] = compute_doppler(bband(offs : offs + ...
            ceil(32 * chip_nsample * max_cfactor)).', pset.chip_dur, pset.chip_frq, ...
            freq_vec(chip_order), bband_fs, pset.cfreq, max_speed, 32);
    else
        state.gamma = 1;
        state.speed = NaN;
    end

    % Skip 32 chips.
    offs = offs + round(32 * bband_fs * pset.chip_dur / state.gamma);
 
    %% Decode packet.
    pkt_len = ceil(pkt_nchip * bband_fs * pset.chip_dur / state.gamma);
    if (offs + pkt_len > length(bband))
        error('janus:rx:sigshort', 'signal too short to contain a valid packet');
    end
    state.pkt_idx = offs;
    
    signal = bband(offs : offs + pkt_len);
    state.process_up_to = (offs + pkt_len) / bband_fs;
    slots = slots(33 : end);
    
    [pkt_bytes, state.pkt_dec_bits, state.pkt_raw_bits, pkt_bit_prob] = demod(pset, signal, bband_fs, slots, PKT_MIN_NBIT, state.gamma, params);
    [pkt, err] = packet_unpack(pkt_bytes);
    
    if (err ~= 0)
        % continue decoding in case of invalid CRC
        disp ('janus:rx:invcrc invalid CRC')
        % error('janus:rx:invcrc', 'invalid CRC');        
    end
    
    if (~isfield(pkt, 'cargo_size') || pkt.cargo_size == 0)
        state.bit_prob = pkt_bit_prob;
        return
    end
    
    offs = offs + pkt_len + 1;
    
    %% Decode optional cargo.
    crg_nbits = pkt.cargo_size * 8;
    crg_nchip = fec_coded_length(crg_nbits, params);
    crg_len = ceil(crg_nchip * bband_fs * pset.chip_dur / state.gamma);

    if (offs + crg_len > length(bband))
        error('janus:rx:sigshort', 'signal too short to contain a valid cargo');
    end
    state.crg_idx = offs;
    
    signal = bband(offs : offs + crg_len);
    state.process_up_to = (offs + pkt_len) / bband_fs;
    slots = hop_pattern(pset.prim_a, pset.prim_q, 32 + pkt_nchip + crg_nchip);
    slots = slots(32 + pkt_nchip + 1 : end);
    
    [pkt.cargo, state.crg_dec_bits, state.crg_raw_bits, crg_bit_prob] ...
        = demod(pset, signal, bband_fs, slots, crg_nbits, state.gamma, params);
    
    try
        plugin = sprintf('plugin_%03d_%02d', pkt.class_id, pkt.app_type);
        eval(['[pkt.app_fields] = ' plugin '(''cargo_decode'', pkt.cargo, '...
              'pkt.cargo_size, pkt.app_fields);']);
    catch ME
        if (verbose)
            disp([plugin ': ' ME.message '.' ]);
        end
    end

    
    state.bit_prob = [pkt_bit_prob; crg_bit_prob];
end
