%+------------------------------------------------------------------------+
%| JANUS is a simple, robust, open standard signalling method for         |
%| underwater communications. See <http://www.januswiki.org> for details. |
%+------------------------------------------------------------------------+
%
% FEC_CODED_LENGTH Return coded length (in bits/chips) for a given payload size.
%
% Inputs:
%   nbits    Number of information bits.
%   params   Parameters structure.
%
% Outputs:
%   nchip    Number of coded bits after FEC and before modulation.
%
function nchip = fec_coded_length(nbits, params)
    defaults;

    if (nargin < 2 || isempty(params))
        params = parameters();
    end

    % Keep the legacy frame duration by default.
    if (params.fec_keep_legacy_length)
        nchip = 2 * (nbits + CONV_ENC_MEM);
        return
    end

    if (strcmpi(params.fec_mode, FEC_MODE_CONV))
        nchip = 2 * (nbits + CONV_ENC_MEM);
    else
        if (params.fec_polar_target_len > 0)
            nchip = fix(params.fec_polar_target_len);
        else
            nchip = 2 * (nbits + CONV_ENC_MEM);
        end
    end
end
