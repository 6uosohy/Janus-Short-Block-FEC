%+------------------------------------------------------------------------+
%| JANUS is a simple, robust, open standard signalling method for         |
%| underwater communications. See <http://www.januswiki.org> for details. |
%+------------------------------------------------------------------------+
%
% POLAR_CA_SCL_DECODE_BITS Decode CRC-aided Polar codewords using SCL.
%
% Inputs:
%   llr_e      Row/column vector of rate-matched LLRs, log(P0/P1).
%   nbits      Number of information bits expected at output.
%   coded_len  Number of coded bits before deinterleaving.
%   params     Parameters structure.
%
% Outputs:
%   dec_bits   Row vector with decoded information bits.
%   dec_info   Decoder statistics (useful for complexity analysis).
%
function [dec_bits, dec_info] = polar_ca_scl_decode_bits(llr_e, nbits, coded_len, params)
    llr_e = double(llr_e(:).');

    [crc_poly, crc_len] = polar_crc_poly(params.fec_polar_crc_len);
    k_total = nbits + crc_len;

    mother_n = polar_choose_mother_length(k_total, params);
    rel_order = polar_reliability_order(mother_n, params, k_total);
    info_idx = sort(rel_order(1 : k_total));
    frozen = true(1, mother_n);
    frozen(info_idx) = false;

    llr_n = polar_rate_recover(llr_e, mother_n, coded_len);

    list_len = max(1, fix(params.fec_polar_list_len));
    list_schedule = polar_scl_schedule(list_len, params);

    dec_bits = false(1, nbits);
    dec_info = struct();
    dec_info.adaptive = params.fec_polar_adaptive_scl;
    dec_info.list_schedule = list_schedule;
    dec_info.attempts = 0;
    dec_info.final_list_len = list_schedule(end);
    dec_info.crc_pass = false;
    dec_info.path_llr_evals = 0;
    dec_info.branch_metric_calls = 0;
    dec_info.candidate_expansions = 0;
    dec_info.max_active = 0;

    for aidx = 1 : length(list_schedule)
        curr_list = list_schedule(aidx);
        [cand_bits, ainfo] = polar_scl_decode(llr_n, frozen, info_idx, nbits, crc_poly, curr_list);

        dec_bits = cand_bits;
        dec_info.attempts = dec_info.attempts + 1;
        dec_info.final_list_len = curr_list;
        dec_info.crc_pass = ainfo.has_valid_crc;
        dec_info.path_llr_evals = dec_info.path_llr_evals + ainfo.path_llr_evals;
        dec_info.branch_metric_calls = dec_info.branch_metric_calls + ainfo.branch_metric_calls;
        dec_info.candidate_expansions = dec_info.candidate_expansions + ainfo.candidate_expansions;
        dec_info.max_active = max(dec_info.max_active, ainfo.max_active);

        if (params.fec_polar_adaptive_scl && ainfo.has_valid_crc)
            break
        end
    end
end

function [dec_bits, info] = polar_scl_decode(llr_n, frozen, info_idx, nbits, crc_poly, list_len)
    n = length(llr_n);

    paths_u = false(list_len, n);
    paths_pm = inf(1, list_len);
    paths_pm(1) = 0.0;
    active = 1;

    info = struct();
    info.has_valid_crc = false;
    info.path_llr_evals = 0;
    info.branch_metric_calls = 0;
    info.candidate_expansions = 0;
    info.max_active = 1;

    for bit_idx = 1 : n
        info.max_active = max(info.max_active, active);
        info.path_llr_evals = info.path_llr_evals + active;

        if (frozen(bit_idx))
            info.branch_metric_calls = info.branch_metric_calls + active;
            for p = 1 : active
                lval = polar_bit_llr(llr_n, paths_u(p, :), bit_idx);
                paths_pm(p) = paths_pm(p) + polar_branch_metric(lval, 0);
                paths_u(p, bit_idx) = false;
            end
        else
            info.branch_metric_calls = info.branch_metric_calls + 2 * active;
            info.candidate_expansions = info.candidate_expansions + 2 * active;

            cand_u = false(2 * active, n);
            cand_pm = inf(1, 2 * active);
            cidx = 0;

            for p = 1 : active
                lval = polar_bit_llr(llr_n, paths_u(p, :), bit_idx);
                for b = 0 : 1
                    cidx = cidx + 1;
                    cand_u(cidx, :) = paths_u(p, :);
                    cand_u(cidx, bit_idx) = logical(b);
                    cand_pm(cidx) = paths_pm(p) + polar_branch_metric(lval, b);
                end
            end

            [~, ord] = sort(cand_pm, 'ascend');
            keep = min(list_len, cidx);
            paths_u(1 : keep, :) = cand_u(ord(1 : keep), :);
            paths_pm(1 : keep) = cand_pm(ord(1 : keep));
            active = keep;
        end
    end

    best_payload = [];
    best_metric = inf;
    best_valid_metric = inf;
    best_valid_payload = [];

    for p = 1 : active
        info_bits = paths_u(p, info_idx);
        payload = info_bits(1 : nbits);

        if (paths_pm(p) < best_metric)
            best_metric = paths_pm(p);
            best_payload = payload;
        end

        if (polar_crc_is_valid(info_bits, crc_poly) && paths_pm(p) < best_valid_metric)
            info.has_valid_crc = true;
            best_valid_metric = paths_pm(p);
            best_valid_payload = payload;
        end
    end

    if (~isempty(best_valid_payload))
        dec_bits = best_valid_payload;
    else
        dec_bits = best_payload;
    end
end

function schedule = polar_scl_schedule(list_len, params)
    if (~params.fec_polar_adaptive_scl)
        schedule = list_len;
        return
    end

    min_list = max(1, min(list_len, fix(params.fec_polar_adaptive_min_list)));
    schedule = min_list;
    curr = min_list;

    while (curr < list_len)
        next = min(list_len, 2 * curr);
        if (next == curr)
            break
        end
        schedule = [schedule, next]; %#ok<AGROW>
        curr = next;
    end

    if (schedule(end) ~= list_len)
        schedule = [schedule, list_len];
    end

    schedule = unique(schedule, 'stable');
end

function llr = polar_bit_llr(llr_in, uhat_in, phi)
    n = length(llr_in);
    if (n == 1)
        llr = llr_in(1);
        return
    end

    half = n / 2;
    if (phi <= half)
        lleft = polar_f(llr_in(1 : half), llr_in(half + 1 : end));
        llr = polar_bit_llr(lleft, uhat_in(1 : half), phi);
    else
        % For the right branch, g() must use left-child partial sums
        % (encoded left subtree), not raw source bits.
        u_left_ps = polar_transform_local(uhat_in(1 : half));
        lright = polar_g(llr_in(1 : half), llr_in(half + 1 : end), u_left_ps);
        llr = polar_bit_llr(lright, uhat_in(half + 1 : end), phi - half);
    end
end

function out = polar_f(a, b)
    % Jacobian-log corrected f() for better accuracy than pure min-sum.
    out = sign(a) .* sign(b) .* min(abs(a), abs(b)) + ...
          log1p(exp(-abs(a + b))) - log1p(exp(-abs(a - b)));
end

function out = polar_g(a, b, u)
    out = b + (1 - 2 * double(u)) .* a;
end

function x = polar_transform_local(u)
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

function metric = polar_branch_metric(llr, bit)
    % Metric increment for candidate decision bit in LLR domain.
    y = -((1 - 2 * bit) * llr);
    if (y > 50)
        metric = y;
    else
        metric = log1p(exp(y));
    end
end

function llr_n = polar_rate_recover(llr_e, mother_n, coded_len)
    e = min(coded_len, length(llr_e));
    llr_n = zeros(1, mother_n);

    if (e <= mother_n)
        llr_n(1 : e) = llr_e(1 : e);
    else
        for idx = 1 : e
            p = mod(idx - 1, mother_n) + 1;
            llr_n(p) = llr_n(p) + llr_e(idx);
        end
    end
end

function valid = polar_crc_is_valid(bits_with_crc, poly)
    if (length(poly) == 1)
        valid = true;
        return
    end

    work = logical(bits_with_crc(:).');
    poly = logical(poly(:).');
    degree = length(poly) - 1;

    for idx = 1 : length(work) - degree
        if (work(idx))
            work(idx : idx + degree) = xor(work(idx : idx + degree), poly);
        end
    end

    valid = ~any(work(end - degree + 1 : end));
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
        error('janus:polar_ca_scl_decode_bits:inv_length', 'k_total exceeds Polar mother length');
    end
end

function [poly, crc_len] = polar_crc_poly(crc_len)
    switch crc_len
      case 0
        poly = true;
      case 6
        poly = logical([1 1 0 0 0 0 1]);
      case 11
        poly = logical([1 1 1 0 0 0 1 0 0 0 0 1]);
      otherwise
        error('janus:polar_ca_scl_decode_bits:inv_crc_len', 'unsupported Polar CRC length');
    end
end
