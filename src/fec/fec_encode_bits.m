%+------------------------------------------------------------------------+
%| JANUS is a simple, robust, open standard signalling method for         |
%| underwater communications. See <http://www.januswiki.org> for details. |
%+------------------------------------------------------------------------+
%
% FEC_ENCODE_BITS Encode and interleave a bit block according to selected FEC mode.
%
% Inputs:
%   bits     Row/column vector with information bits.
%   params   Parameters structure.
%
% Outputs:
%   coded    Row vector with interleaved coded bits.
%   info     Structure with encoder metadata.
%
function [coded, info] = fec_encode_bits(bits, params)
    defaults;

    if (nargin < 2 || isempty(params))
        params = parameters();
    end

    bits = logical(bits(:).');

    info = struct();
    info.mode = lower(params.fec_mode);
    info.ninfo = length(bits);

    switch info.mode
      case FEC_MODE_CONV
        trellis = poly2trellis(CONV_ENC_CLEN, CONV_ENC_CGEN);
        conv_out = convenc([bits, zeros(1, CONV_ENC_MEM)], trellis);
        [coded, q] = interleave(conv_out);
        info.interleaver_prime = q;
        info.ncoded = length(coded);

      case FEC_MODE_POLAR
        target_len = fec_coded_length(length(bits), params);
        [polar_out, polar_info] = polar_ca_encode_bits(bits, target_len, params);
        [coded, q] = interleave(polar_out);
        info.interleaver_prime = q;
        info.ncoded = length(coded);
        info.polar = polar_info;

      otherwise
        error('janus:fec_encode_bits:inv_mode', 'unsupported FEC mode');
    end

    coded = logical(coded(:).');
end
