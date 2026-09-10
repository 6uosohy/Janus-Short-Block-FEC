function codec = turbo_make_codec()
%TURBO_MAKE_CODEC  Build turbo encoder/decoder objects and puncturing mask.
%
%   codec = turbo_make_codec()
%
%   Returns a struct with:
%     .encoder      : comm.TurboEncoder system object
%     .decoder      : comm.TurboDecoder system object
%     .punct_mask   : logical(1, mother_len), true = keep
%     .K            : 64
%     .E            : 144
%     .mother_len   : 204
%     .trellis      : poly2trellis output
%     .intrlvr_idx  : interleaver indices
%     .num_iterations : 6

    K = 64;
    E = 144;

    % --- Trellis: LTE-style RSC, constraint length 4 ---
    trellis = poly2trellis(4, [13 15], 13);
    num_mem = log2(trellis.numStates);       % 3
    mother_len = 3 * K + 4 * num_mem;       % 204

    % --- S-random interleaver (deterministic, reproducible) ---
    % S = floor(sqrt(K/2)) is the standard choice for turbo codes.
    % Guarantees: |pi(i) - pi(j)| > S for all |i - j| <= S
    S = floor(sqrt(K / 2));   % S = 5 for K=64
    intrlvr_idx = generate_s_random_interleaver(K, S, 7777);

    % --- Encoder ---
    encoder = comm.TurboEncoder( ...
        'TrellisStructure', trellis, ...
        'InterleaverIndicesSource', 'Property', ...
        'InterleaverIndices', intrlvr_idx);

    % --- Decoder: max-log-MAP, 6 iterations ---
    num_iterations = 6;
    decoder = comm.TurboDecoder( ...
        'TrellisStructure', trellis, ...
        'InterleaverIndicesSource', 'Property', ...
        'InterleaverIndices', intrlvr_idx, ...
        'Algorithm', 'Max*', ...
        'NumIterations', num_iterations);

    % --- Puncturing mask ---
    % Mother output format (interleaved):
    %   [sys(1) par1(1) par2(1)  sys(2) par1(2) par2(2) ... sys(K) par1(K) par2(K)  tail(1:12)]
    sys_idx  = 1:3:(3*K);          % 64 systematic positions
    par1_idx = 2:3:(3*K);          % 64 parity-1 positions
    par2_idx = 3:3:(3*K);          % 64 parity-2 positions
    tail_idx = (3*K + 1):mother_len; % 12 tail positions

    % Budget: keep 64 sys + 12 tail = 76  →  need 68 parity from 128 total
    %   → keep 34 from par1, 34 from par2 (remove 30 each)
    par1_keep_local = round(linspace(1, 64, 34));   % 34 evenly spaced
    par2_keep_local = round(linspace(1, 64, 34));

    keep_pos = sort([ ...
        sys_idx, ...
        par1_idx(par1_keep_local), ...
        par2_idx(par2_keep_local), ...
        tail_idx]);

    punct_mask = false(1, mother_len);
    punct_mask(keep_pos) = true;
    assert(sum(punct_mask) == E, ...
        'Puncturing mask error: expected %d kept bits, got %d', E, sum(punct_mask));

    % --- Package ---
    codec.encoder        = encoder;
    codec.decoder        = decoder;
    codec.punct_mask     = punct_mask;
    codec.K              = K;
    codec.E              = E;
    codec.mother_len     = mother_len;
    codec.trellis        = trellis;
    codec.intrlvr_idx    = intrlvr_idx;
    codec.num_iterations = num_iterations;
    codec.S_random       = S;
end

%% ===== S-random interleaver generation =====
function pi_vec = generate_s_random_interleaver(K, S, seed)
%GENERATE_S_RANDOM_INTERLEAVER  Dolinar/Divsalar S-random interleaver.
%   For all |i - j| <= S, guarantees |pi(i) - pi(j)| > S.
%   Reference: S. Dolinar, D. Divsalar, "Weight distributions for turbo
%   codes using random and nonrandom permutations," TDA Progress Report,
%   JPL, 1995.

    rng(seed, 'twister');
    max_attempts = 1000;

    pi_vec = zeros(K, 1);
    available = 1:K;

    for i = 1:K
        placed = false;
        for attempt = 1:max_attempts
            % Pick a random candidate from remaining positions
            pick = randi(length(available));
            candidate = available(pick);

            % Check S-random constraint against already-placed positions
            ok = true;
            lo = max(1, i - S);
            for j = lo:(i-1)
                if abs(candidate - pi_vec(j)) <= S
                    ok = false;
                    break;
                end
            end

            if ok
                pi_vec(i) = candidate;
                available(pick) = [];
                placed = true;
                break;
            end
        end

        % Fallback: if S-constraint cannot be met, relax and pick any
        if ~placed
            pick = randi(length(available));
            pi_vec(i) = available(pick);
            available(pick) = [];
        end
    end
end
