%+------------------------------------------------------------------------+
%| JANUS is a simple, robust, open standard signalling method for         |
%| underwater communications. See <http://www.januswiki.org> for details. |
%+------------------------------------------------------------------------+
%
% FEC_DECODE_SOFT_BITS Decode an interleaved soft bit sequence.
%
% Inputs:
%   bit_prob   Column/row vector of probabilities P(bit=1), 0 < p < 1.
%   nbits      Number of information bits to recover.
%   params     Parameters structure.
%
% Outputs:
%   dec_bits   Row vector with decoded bits.
%   dlv_seq    Deinterleaved sequence fed to the selected decoder.
%   dec_info   Decoder statistics (mode dependent).
%
function [dec_bits, dlv_seq, dec_info] = fec_decode_soft_bits(bit_prob, nbits, params)
    defaults;

    if (nargin < 3 || isempty(params))
        params = parameters();
    end

    bit_prob = bit_prob(:);
    bit_prob = min(max(bit_prob, 1e-6), 1 - 1e-6);
    nchip = length(bit_prob);

    q = interleaver_prime(nchip);
    need_info = (nargout >= 3);

    switch (lower(params.fec_mode))
      case FEC_MODE_CONV
        soft_u8 = min(max(round(bit_prob * 255), 0), 255);
        dlv_seq = deinterleave(soft_u8', q)';
        trellis = poly2trellis(CONV_ENC_CLEN, CONV_ENC_CGEN);
        dec_bits = vitdec(dlv_seq, trellis, min(9 * 5, length(dlv_seq) / 2), 'trunc', 'soft', 8);
        dec_bits = dec_bits(1 : nbits);
        if (need_info)
            dec_info = struct();
            dec_info.mode = FEC_MODE_CONV;
            dec_info.adaptive = false;
            dec_info.attempts = 1;
            dec_info.final_list_len = 0;
            dec_info.crc_pass = true;
            dec_info.path_llr_evals = NaN;
            dec_info.branch_metric_calls = NaN;
            dec_info.candidate_expansions = NaN;
            dec_info.max_active = NaN;
        end

      case FEC_MODE_POLAR
        dlv_seq = deinterleave(bit_prob', q)';
        llr = prob_to_llr(dlv_seq);
        if (need_info)
            [dec_bits, dec_info] = polar_ca_scl_decode_bits(llr, nbits, nchip, params);
            dec_info.mode = FEC_MODE_POLAR;
        else
            dec_bits = polar_ca_scl_decode_bits(llr, nbits, nchip, params);
        end

      otherwise
        error('janus:fec_decode_soft_bits:inv_mode', 'unsupported FEC mode');
    end

    dec_bits = logical(dec_bits(:).');
end

function llr = prob_to_llr(prob1)
    % LLR definition used in this codebase: log(P0 / P1).
    llr = log((1 - prob1) ./ prob1);
    llr = llr(:).';
end
