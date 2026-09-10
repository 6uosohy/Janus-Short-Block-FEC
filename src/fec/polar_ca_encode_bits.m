%+------------------------------------------------------------------------+
%| JANUS is a simple, robust, open standard signalling method for         |
%| underwater communications. See <http://www.januswiki.org> for details. |
%+------------------------------------------------------------------------+
%
% POLAR_CA_ENCODE_BITS Encode bits with CRC-aided Polar coding.
%
% Inputs:
%   bits        Row/column vector with payload bits.
%   target_len  Number of coded bits after rate matching.
%   params      Parameters structure.
%
% Outputs:
%   coded       Coded bit row vector.
%   info        Encoder metadata.
%
function [coded, info] = polar_ca_encode_bits(bits, target_len, params)
    bits = logical(bits(:).');

    [crc_poly, crc_len] = polar_crc_poly(params.fec_polar_crc_len);
    payload_crc = polar_crc_attach(bits, crc_poly);
    k_total = length(payload_crc);

    mother_n = polar_choose_mother_length(k_total, params);
    rel_order = polar_reliability_order(mother_n, params, k_total);
    info_idx = sort(rel_order(1 : k_total));

    u = false(1, mother_n);
    u(info_idx) = payload_crc;

    x = polar_transform(u);
    coded = polar_rate_match(x, target_len);

    info = struct();
    info.crc_len = crc_len;
    info.k_total = k_total;
    info.mother_n = mother_n;
    info.target_len = target_len;
    info.info_idx = info_idx;
end

function n = polar_choose_mother_length(k_total, params)
    if (params.fec_polar_force_n > 0)
        n = 2 ^ nextpow2(params.fec_polar_force_n);
    else
        n = 2 ^ nextpow2(k_total);
        n = max(n, params.fec_polar_min_n);
    end

    n = min(n, params.fec_polar_max_n);
    if (k_total > n)
        error('janus:polar_ca_encode_bits:inv_length', 'k_total exceeds Polar mother length');
    end
end

function out = polar_crc_attach(bits, poly)
    if (length(poly) == 1)
        out = bits;
        return
    end
    crc = polar_crc_remainder(bits, poly);
    out = [bits, crc];
end

function rem_bits = polar_crc_remainder(bits, poly)
    bits = logical(bits(:).');
    poly = logical(poly(:).');
    degree = length(poly) - 1;

    work = [bits, false(1, degree)];
    for idx = 1 : length(bits)
        if (work(idx))
            work(idx : idx + degree) = xor(work(idx : idx + degree), poly);
        end
    end

    rem_bits = work(end - degree + 1 : end);
end

function x = polar_transform(u)
    x = logical(u(:).');
    n = length(x);
    stages = log2(n);

    for stage = 1 : stages
        step = 2 ^ stage;
        half = step / 2;
        for idx = 1 : step : n
            i1 = idx : idx + half - 1;
            i2 = idx + half : idx + step - 1;
            x(i1) = xor(x(i1), x(i2));
        end
    end
end

function y = polar_rate_match(x, e)
    n = length(x);
    if (e <= n)
        y = x(1 : e);
    else
        idx = mod(0 : e - 1, n) + 1;
        y = x(idx);
    end
end

function [poly, crc_len] = polar_crc_poly(crc_len)
    switch crc_len
      case 0
        poly = true;
      case 6
        % g(D) = D^6 + D^5 + 1
        poly = logical([1 1 0 0 0 0 1]);
      case 11
        % g(D) = D^11 + D^10 + D^9 + D^5 + 1
        poly = logical([1 1 1 0 0 0 1 0 0 0 0 1]);
      otherwise
        error('janus:polar_ca_encode_bits:inv_crc_len', 'unsupported Polar CRC length');
    end
end
