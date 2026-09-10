%+------------------------------------------------------------------------+
%| JANUS is a simple, robust, open standard signalling method for         |
%| underwater communications. See <http://www.januswiki.org> for details. |
%+------------------------------------------------------------------------+
%
% POLAR_RELIABILITY_ORDER Return Polar bit-channel reliability ranking.
%
% Inputs:
%   n         Mother code length (power of two).
%   params    Parameters structure.
%   k_total   Number of information+CRC bits (optional).
%
% Output:
%   order     Indices sorted from most reliable to least reliable.
%
function order = polar_reliability_order(n, params, k_total)
    defaults;

    if (nargin < 2 || isempty(params))
        params = parameters();
    end

    if (nargin < 3 || isempty(k_total))
        k_total = fix(n / 2);
    end
    k_total = max(1, min(n, fix(k_total)));

    method = lower(params.fec_polar_reliability_method);
    switch method
      case 'pw'
        order = reliability_order_pw(n, params.fec_polar_pw_beta);
      case 'ga'
        order = reliability_order_ga(n, params.fec_polar_design_ebn0_db, k_total);
      otherwise
        error('janus:polar_reliability_order:inv_method', 'unsupported reliability method');
    end
end

function order = reliability_order_pw(n, beta)
    depth = log2(n);
    pw = zeros(1, n);

    for idx = 0 : n - 1
        w = 0.0;
        for bit = 0 : depth - 1
            if (bitget(uint32(idx), bit + 1))
                w = w + beta ^ bit;
            end
        end
        pw(idx + 1) = w + idx * 1e-12;
    end

    [~, order] = sort(pw, 'descend');
end

function order = reliability_order_ga(n, design_ebn0_db, k_total)
    rate_eff = max(1e-4, min(0.9999, k_total / n));
    ebn0_lin = 10 ^ (design_ebn0_db / 10);
    m0 = 4 * rate_eff * ebn0_lin;
    means = m0;

    depth = log2(n);
    for stage = 1 : depth
        prev = means;
        means = zeros(1, 2 ^ stage);
        oidx = 1;

        for idx = 1 : length(prev)
            m = prev(idx);
            left = ga_phi_inv(1 - (1 - ga_phi(m)) ^ 2);
            right = 2 * m;
            means(oidx) = left;
            means(oidx + 1) = right;
            oidx = oidx + 2;
        end
    end

    [~, order] = sort(means, 'descend');
end

function y = ga_phi(x)
    x = max(x, 1e-12);
    y = exp(-0.4527 .* (x .^ 0.86) + 0.0218);
    y = min(max(y, 1e-300), 1 - 1e-12);
end

function x = ga_phi_inv(y)
    y = min(max(y, 1e-300), 1 - 1e-12);
    base = (-log(y) - 0.0218) / 0.4527;
    base = max(base, 1e-12);
    x = base .^ (1 / 0.86);
    x = max(x, 1e-12);
end
