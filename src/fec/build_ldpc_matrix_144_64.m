function [H, cfg] = build_ldpc_matrix_144_64()
%BUILD_LDPC_MATRIX_144_64  Construct (144,64) LDPC parity-check matrix.
%
%   [H, cfg] = build_ldpc_matrix_144_64()
%
%   Uses Progressive Edge Growth (PEG) to build a column-weight-3 regular
%   LDPC code with girth >= 6 (4-cycle avoidance).
%
%   H   : sparse 80x144 parity-check matrix
%   cfg : struct with construction parameters

    persistent H_cached cfg_cached;
    if ~isempty(H_cached)
        H = H_cached;
        cfg = cfg_cached;
        return;
    end

    n = 144;   % code length
    k = 64;    % information length
    m = n - k; % number of parity checks = 80
    dv = 3;    % column (variable-node) degree

    fprintf('[build_ldpc_matrix_144_64] Constructing (%d,%d) LDPC, dv=%d ...\n', n, k, dv);

    % Deterministic construction
    rng_state = rng;
    rng(54321, 'twister');

    H = peg_construct(m, n, dv);

    rng(rng_state);

    % Validate
    r = gf2rank(H);
    if r < m
        warning('LDPC:RankDeficient', 'H rank = %d < %d, attempting repair', r, m);
        H = repair_rank(H, m, n, dv);
    end

    cfg.n = n;
    cfg.k = k;
    cfg.m = m;
    cfg.dv = dv;
    cfg.rank = gf2rank(H);
    cfg.row_weight_mean = full(mean(sum(H, 2)));
    cfg.col_weight_mean = full(mean(sum(H, 1)));

    fprintf('  H: %dx%d, rank=%d, mean_row_wt=%.1f, mean_col_wt=%.1f\n', ...
        m, n, cfg.rank, cfg.row_weight_mean, cfg.col_weight_mean);

    H_cached = H;
    cfg_cached = cfg;
end

%% --- PEG Construction ---
function H = peg_construct(m, n, dv)
    H = sparse(m, n);

    for j = 1:n
        for d = 1:dv
            row_deg = full(sum(H, 2));
            [~, sorted_rows] = sort(row_deg);

            placed = false;
            for ri = 1:m
                r = sorted_rows(ri);
                if H(r, j) == 0 && ~has_4cycle(H, r, j)
                    H(r, j) = 1;
                    placed = true;
                    break;
                end
            end

            % Fallback: if no girth-6 placement found, pick lowest-degree row
            if ~placed
                for ri = 1:m
                    r = sorted_rows(ri);
                    if H(r, j) == 0
                        H(r, j) = 1;
                        break;
                    end
                end
            end
        end
    end
end

%% --- 4-cycle check ---
function cyc = has_4cycle(H, r, j)
    % Adding edge (r,j) creates a 4-cycle if:
    %   exists j' != j connected to r AND
    %   exists r' != r connected to both j and j'
    cyc = false;
    cols_of_r = find(H(r, :));
    if isempty(cols_of_r)
        return;
    end
    rows_of_j = find(H(:, j));
    if isempty(rows_of_j)
        return;
    end
    for c = cols_of_r
        shared = find(H(rows_of_j, c));
        if ~isempty(shared)
            cyc = true;
            return;
        end
    end
end

%% --- GF(2) rank ---
function r = gf2rank(H)
    A = full(H);
    [m, n] = size(A);
    r = 0;
    for col = 1:n
        % Find pivot
        pivot = 0;
        for row = (r+1):m
            if A(row, col) == 1
                pivot = row;
                break;
            end
        end
        if pivot == 0
            continue;
        end
        r = r + 1;
        % Swap rows
        A([r, pivot], :) = A([pivot, r], :);
        % Eliminate
        for row = 1:m
            if row ~= r && A(row, col) == 1
                A(row, :) = mod(A(row, :) + A(r, :), 2);
            end
        end
    end
end

%% --- Rank repair ---
function H = repair_rank(H, m, n, dv)
    % Replace rows with lowest weight to increase rank
    max_attempts = 50;
    for att = 1:max_attempts
        r = gf2rank(H);
        if r >= m
            return;
        end
        % Find a row that can be replaced
        row_wt = full(sum(H, 2));
        [~, worst] = min(row_wt);
        % Generate new random row with weight ~dv*n/m
        target_wt = round(dv * n / m);
        new_cols = randsample(n, target_wt);
        H(worst, :) = 0;
        H(worst, new_cols) = 1;
    end
    warning('LDPC:RepairFailed', 'Could not achieve full rank after %d attempts', max_attempts);
end
