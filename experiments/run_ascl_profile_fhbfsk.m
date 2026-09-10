function out = run_ascl_profile_fhbfsk(cfg)
%RUN_ASCL_PROFILE_FHBFSK  Profile Adaptive-SCL behavior over FH-BFSK AWGN.
%
%   Runs only Polar Adaptive-SCL through FH-BFSK waveform chain and records
%   per-SNR average attempts and average final list size for Fig.2.
%
%   Usage:
%     out = run_ascl_profile_fhbfsk();
%     out = run_ascl_profile_fhbfsk(cfg);

    if nargin < 1, cfg = struct(); end

    % Defaults
    if ~isfield(cfg, 'K'),          cfg.K = 64;           end
    if ~isfield(cfg, 'E'),          cfg.E = 144;          end
    if ~isfield(cfg, 'ebn0_db'),    cfg.ebn0_db = 5:0.5:12; end
    if ~isfield(cfg, 'max_frames'), cfg.max_frames = 5000; end
    if ~isfield(cfg, 'bband_fs'),   cfg.bband_fs = 44100; end
    if ~isfield(cfg, 'fec_polar_list_len'),         cfg.fec_polar_list_len = 8;  end
    if ~isfield(cfg, 'fec_polar_crc_len'),          cfg.fec_polar_crc_len = 11;  end
    if ~isfield(cfg, 'fec_polar_reliability_method'), cfg.fec_polar_reliability_method = 'ga'; end
    if ~isfield(cfg, 'fec_polar_design_ebn0_db'),   cfg.fec_polar_design_ebn0_db = 2.0; end
    if ~isfield(cfg, 'fec_polar_adaptive_min_list'), cfg.fec_polar_adaptive_min_list = 4; end
    if ~isfield(cfg, 'rng_seed'),   cfg.rng_seed = 42;    end
    if ~isfield(cfg, 'asset_dir')
        cfg.asset_dir = fullfile(fileparts(mfilename('fullpath')), ...
            '..', 'data', 'fhbfsk_awgn');
    end

    defaults;

    fprintf('\n============================================\n');
    fprintf('  ASCL Profile (FH-BFSK AWGN)\n');
    fprintf('  L=%d, L0=%d, %d SNR pts, %d fr/pt\n', ...
        cfg.fec_polar_list_len, cfg.fec_polar_adaptive_min_list, ...
        length(cfg.ebn0_db), cfg.max_frames);
    fprintf('============================================\n');

    % Build Polar Adaptive-SCL params
    params = parameters();
    params.fec_mode = FEC_MODE_POLAR;
    params.fec_keep_legacy_length = 1;
    params.fec_polar_list_len = cfg.fec_polar_list_len;
    params.fec_polar_crc_len  = cfg.fec_polar_crc_len;
    params.fec_polar_reliability_method = cfg.fec_polar_reliability_method;
    params.fec_polar_design_ebn0_db = cfg.fec_polar_design_ebn0_db;
    params.fec_polar_adaptive_scl = 1;
    params.fec_polar_adaptive_min_list = cfg.fec_polar_adaptive_min_list;
    params.verbose = 0;

    % Build JANUS pset
    pset = pset_new(1, 'JANUS default', 11520, 4160);

    % Sanity check
    bits = logical(randi([0 1], 1, cfg.K));
    coded = fec_encode_bits(bits, params);
    bband = fhbfsk_mod(coded, pset, cfg.bband_fs);
    bp    = fhbfsk_demod(bband, pset, cfg.bband_fs, cfg.E);
    [dec, ~, di] = fec_decode_soft_bits(bp, cfg.K, params);
    assert(~any(xor(bits, dec)), 'Sanity check FAILED');
    fprintf('  Sanity check PASSED (dec_info fields: %s)\n', strjoin(fieldnames(di), ', '));

    % Run profiling
    nsnr = length(cfg.ebn0_db);
    code_rate = cfg.K / cfg.E;

    avg_attempts  = zeros(1, nsnr);
    avg_list_size = zeros(1, nsnr);
    bler          = zeros(1, nsnr);

    rng(cfg.rng_seed, 'twister');

    for si = 1:nsnr
        ebn0 = cfg.ebn0_db(si);
        ebn0_lin = 10^(ebn0 / 10);

        sum_attempts = 0;
        sum_listsize = 0;
        fc = 0; fe = 0;

        for fi = 1:cfg.max_frames
            bits  = logical(randi([0 1], 1, cfg.K));
            coded = fec_encode_bits(bits, params);

            % FH-BFSK mod -> AWGN -> demod
            bband = fhbfsk_mod(coded, pset, cfg.bband_fs);
            nsamp = length(bband);
            P_sig = mean(abs(bband).^2);
            chip_nsample = round(pset.chip_dur * cfg.bband_fs);
            E_s = P_sig * chip_nsample / cfg.bband_fs;
            E_b = E_s / code_rate;
            N0  = E_b / ebn0_lin;
            noise_var = N0 * cfg.bband_fs;
            noise = sqrt(noise_var/2) * (randn(nsamp,1) + 1i*randn(nsamp,1));
            y = bband + noise;

            bp = fhbfsk_demod(y, pset, cfg.bband_fs, cfg.E);

            % Decode with dec_info
            [dec_bits, ~, dec_info] = fec_decode_soft_bits(bp, cfg.K, params);

            % Record ASCL metrics
            if isfield(dec_info, 'attempts')
                sum_attempts = sum_attempts + dec_info.attempts;
            elseif isfield(dec_info, 'num_attempts')
                sum_attempts = sum_attempts + dec_info.num_attempts;
            else
                sum_attempts = sum_attempts + 1;
            end

            if isfield(dec_info, 'final_list_len')
                sum_listsize = sum_listsize + dec_info.final_list_len;
            elseif isfield(dec_info, 'list_size')
                sum_listsize = sum_listsize + dec_info.list_size;
            else
                sum_listsize = sum_listsize + cfg.fec_polar_list_len;
            end

            nerr = nnz(xor(bits, dec_bits));
            fe = fe + (nerr > 0);
            fc = fc + 1;
        end

        avg_attempts(si)  = sum_attempts / fc;
        avg_list_size(si) = sum_listsize / fc;
        bler(si) = fe / fc;

        fprintf('  Eb/N0=%5.1f dB | BLER=%.3e | avg_attempts=%.3f | avg_L=%.2f\n', ...
            ebn0, bler(si), avg_attempts(si), avg_list_size(si));
    end

    % Save results
    if ~exist(cfg.asset_dir, 'dir'), mkdir(cfg.asset_dir); end
    ascl_profile = struct();
    ascl_profile.ebn0_db       = cfg.ebn0_db;
    ascl_profile.avg_attempts  = avg_attempts;
    ascl_profile.avg_list_size = avg_list_size;
    ascl_profile.bler          = bler;
    ascl_profile.L             = cfg.fec_polar_list_len;
    ascl_profile.L0            = cfg.fec_polar_adaptive_min_list;
    ascl_profile.max_frames    = cfg.max_frames;
    ascl_profile.bband_fs      = cfg.bband_fs;

    mat_path = fullfile(cfg.asset_dir, 'ascl_profile.mat');
    save(mat_path, '-struct', 'ascl_profile');
    fprintf('\n  Saved: %s\n', mat_path);

    % Generate Fig.2
    fig_path = plot_complexity_figure(ascl_profile, cfg);
    fprintf('  Saved: %s\n', fig_path);

    out = ascl_profile;
    out.fig_path = fig_path;
    out.mat_path = mat_path;
end

function fig_path = plot_complexity_figure(prof, cfg)
    f = figure('Visible', 'off', 'Position', [100 100 720 700]);

    %% Top subplot: Theoretical operations bar chart (L=8)
    subplot(2,1,1);
    decoders = {'Conv\newline(Viterbi)', 'Turbo\newline(MAP\times6)', ...
                'LDPC\newline(NMS\times50)', 'Polar SCL\newline(L=8)', ...
                'Polar ASCL\newline(L_0=4, best)'};
    ops = [36864, 6144, 21600, 7168, 3584];
    colors = [0.3 0.6 0.9;   % Conv - blue
              0.9 0.5 0.3;   % Turbo - orange
              0.9 0.8 0.2;   % LDPC - yellow
              0.6 0.3 0.7;   % Polar SCL - purple
              0.4 0.7 0.4];  % Polar ASCL - green

    b = bar(ops, 'FaceColor', 'flat');
    for k = 1:5, b.CData(k,:) = colors(k,:); end
    set(gca, 'XTickLabel', decoders, 'FontSize', 8);
    ylabel('Operations / frame');
    title(sprintf('Theoretical Decoding Complexity (K=%d, E=%d)', cfg.K, cfg.E));
    grid on;

    % Add value labels
    for k = 1:5
        text(k, ops(k) + 800, sprintf('%,d', ops(k)), ...
            'HorizontalAlignment', 'center', 'FontSize', 7);
    end

    %% Bottom subplot: ASCL behavior
    subplot(2,1,2);
    yyaxis left;
    plot(prof.ebn0_db, prof.avg_attempts, 'g-o', 'LineWidth', 1.5, 'MarkerSize', 5);
    ylabel('Avg. decoding attempts');
    ylim([0.9, 2.1]);

    yyaxis right;
    plot(prof.ebn0_db, prof.avg_list_size, 'm-s', 'LineWidth', 1.5, 'MarkerSize', 5);
    ylabel('Avg. final list size');
    ylim([prof.L0 - 0.5, prof.L + 0.5]);

    % Reference lines
    hold on;
    yyaxis left;
    yline(1.0, '--', 'Single pass', 'Color', [0.5 0.5 0.5], 'Alpha', 0.6);

    yyaxis right;
    yline(prof.L0, '--', sprintf('L_0=%d', prof.L0), 'Color', [0.7 0.3 0.7], 'Alpha', 0.6);
    yline(prof.L, '--', sprintf('L=%d', prof.L), 'Color', [0.7 0.3 0.7], 'Alpha', 0.6);

    xlabel('E_b/N_0 (dB)');
    title(sprintf('Adaptive-SCL Behavior (L_0=%d \\rightarrow %d, FH-BFSK AWGN)', prof.L0, prof.L));
    grid on;
    legend({'Avg. attempts', 'Avg. list size'}, 'Location', 'east');

    fig_path = fullfile(cfg.asset_dir, 'fhbfsk_ascl_complexity.png');
    exportgraphics(f, fig_path, 'Resolution', 300);
    close(f);

    % Also copy to figures/ for paper
    fig_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'oceans2026_submission', 'figures');
    if exist(fig_dir, 'dir')
        copyfile(fig_path, fullfile(fig_dir, 'awgn_ascl_attempts.png'));
        fprintf('  Copied to figures/awgn_ascl_attempts.png\n');
    end
end
