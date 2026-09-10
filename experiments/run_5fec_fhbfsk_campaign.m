function out = run_5fec_fhbfsk_campaign(cfg)
%RUN_5FEC_FHBFSK_CAMPAIGN  5-FEC comparison using actual FH-BFSK waveforms.
%
%   Unlike run_5fec_uwa_campaign (BPSK baseband equivalent), this script
%   uses actual JANUS FH-BFSK modulation (fhbfsk_mod) and non-coherent
%   energy detection (fhbfsk_demod) for a faithful JANUS PHY simulation.
%
%   Supports two channel modes:
%     'awgn'  — complex AWGN added to waveform
%     'uwa'   — waveform-level multipath (Rician 3-tap) + AWGN + impulsive
%
%   Usage:
%     out = run_5fec_fhbfsk_campaign();                % AWGN default
%     cfg.channel_mode = 'uwa'; out = run_5fec_fhbfsk_campaign(cfg);
%
%   Key cfg fields:
%     channel_mode        'awgn' or 'uwa'
%     ebn0_db, max_frames, min_frame_errors, bband_fs
%     (UWA) uwa_tap_delays, uwa_tap_gains_db, uwa_fading, uwa_k_factor_db
%     fec_polar_list_len, fec_polar_adaptive_min_list, asset_dir

    if nargin < 1, cfg = struct(); end
    cfg = fill_defaults(cfg);
    ensure_dir(cfg.asset_dir);

    defaults;

    fprintf('\n############################################################\n');
    fprintf('#  5-FEC FH-BFSK CAMPAIGN  (%s)                           #\n', upper(cfg.channel_mode));
    fprintf('#  K=%d, E=%d, fs=%d Hz, %d SNR pts, %d fr/pt            #\n', ...
        cfg.K, cfg.E, cfg.bband_fs, length(cfg.ebn0_db), cfg.max_frames);
    if strcmp(cfg.channel_mode, 'uwa')
        fprintf('#  UWA: delays=[%s], gains=[%s] dB, %s K=%.0f dB        #\n', ...
            num2str(cfg.uwa_tap_delays), num2str(cfg.uwa_tap_gains_db), ...
            cfg.uwa_fading, cfg.uwa_k_factor_db);
    end
    fprintf('############################################################\n');

    %% ===== Phase 1: Build JANUS pset + codecs =====
    fprintf('\n[Phase 1] Building JANUS pset and codecs ...\n');

    pset = pset_new(1, 'JANUS default (9-14 kHz)', 11520, 4160);
    fprintf('  pset: cfreq=%d Hz, bw=%d Hz, chip_frq=%.1f Hz, chip_dur=%.4f s\n', ...
        pset.cfreq, pset.bwidth, pset.chip_frq, pset.chip_dur);

    % Conv + Polar (via JANUS framework)
    params_conv = parameters();
    params_conv.fec_mode = FEC_MODE_CONV;
    params_conv.fec_keep_legacy_length = 1;
    params_conv.verbose = 0;

    params_polar_fix = parameters();
    params_polar_fix.fec_mode = FEC_MODE_POLAR;
    params_polar_fix.fec_keep_legacy_length = 1;
    params_polar_fix.fec_polar_list_len        = cfg.fec_polar_list_len;
    params_polar_fix.fec_polar_crc_len         = cfg.fec_polar_crc_len;
    params_polar_fix.fec_polar_reliability_method = cfg.fec_polar_reliability_method;
    params_polar_fix.fec_polar_design_ebn0_db  = cfg.fec_polar_design_ebn0_db;
    params_polar_fix.fec_polar_adaptive_scl    = 0;
    params_polar_fix.verbose = 0;

    params_polar_adp = params_polar_fix;
    params_polar_adp.fec_polar_adaptive_scl      = 1;
    params_polar_adp.fec_polar_adaptive_min_list = cfg.fec_polar_adaptive_min_list;

    % Turbo + LDPC (standalone)
    clear turbo_encode_janus turbo_decode_janus turbo_make_codec;
    clear ldpc_encode_janus ldpc_decode_janus ldpc_make_codec build_ldpc_matrix_144_64;
    turbo_codec = turbo_make_codec();
    ldpc_codec  = ldpc_make_codec();

    fprintf('  Conv:  K=%d, E=%d\n', cfg.K, fec_coded_length(cfg.K, params_conv));
    fprintf('  Turbo: K=%d, E=%d, iter=%d\n', turbo_codec.K, turbo_codec.E, turbo_codec.num_iterations);
    fprintf('  LDPC:  K=%d, E=%d, max_iter=%d\n', ldpc_codec.K, ldpc_codec.E, ldpc_codec.max_iter);
    fprintf('  Polar: K=%d, E=%d, L=%d, CRC=%d\n', ...
        cfg.K, fec_coded_length(cfg.K, params_polar_fix), cfg.fec_polar_list_len, cfg.fec_polar_crc_len);
    fprintf('  Adaptive: L0=%d -> Lmax=%d\n', cfg.fec_polar_adaptive_min_list, cfg.fec_polar_list_len);

    %% ===== Phase 2: Sanity check (noiseless waveform round-trip) =====
    fprintf('\n[Phase 2] Noiseless FH-BFSK round-trip sanity check ...\n');

    for trial = 1:cfg.sanity_trials
        bits = logical(randi([0 1], 1, cfg.K));
        coded = fec_encode_bits(bits, params_conv);
        bband = fhbfsk_mod(coded, pset, cfg.bband_fs);
        bp    = fhbfsk_demod(bband, pset, cfg.bband_fs, cfg.E);
        dec   = fec_decode_soft_bits(bp, cfg.K, params_conv);
        if any(xor(bits, dec))
            error('Sanity FAIL: FH-BFSK round-trip error at trial %d', trial);
        end
    end
    fprintf('  FH-BFSK round-trip: PASS (%d trials)\n', cfg.sanity_trials);

    % Turbo/LDPC LLR sign detection (reuse logic from run_5fec_uwa_campaign)
    turbo_codec = detect_llr_sign_turbo(turbo_codec, pset, cfg);
    ldpc_codec  = detect_llr_sign_ldpc(ldpc_codec, pset, cfg);

    %% ===== Phase 3: Run 5-FEC campaigns =====
    mode_names = { ...
        'Conv (Viterbi)', ...
        'Turbo (max-log-MAP)', ...
        'LDPC (norm. min-sum)', ...
        'Polar Fixed-SCL', ...
        'Polar Adaptive-SCL' };
    nmodes = length(mode_names);
    nsnr   = length(cfg.ebn0_db);

    bler       = zeros(nmodes, nsnr);
    ber        = zeros(nmodes, nsnr);
    nframes    = zeros(nmodes, nsnr);
    nerr_frame = zeros(nmodes, nsnr);
    nerr_bit   = zeros(nmodes, nsnr);

    fprintf('\n========== [Mode 1/5] Conv (Viterbi) ==========\n');
    rng(cfg.rng_seed_base + 1, 'twister');
    r1 = run_fhbfsk_loop_janus(params_conv, pset, cfg);
    [bler(1,:), ber(1,:), nframes(1,:), nerr_frame(1,:), nerr_bit(1,:)] = unpack(r1);

    fprintf('\n========== [Mode 2/5] Turbo (max-log-MAP) ==========\n');
    rng(cfg.rng_seed_base + 2, 'twister');
    r2 = run_fhbfsk_loop_turbo(turbo_codec, pset, cfg);
    [bler(2,:), ber(2,:), nframes(2,:), nerr_frame(2,:), nerr_bit(2,:)] = unpack(r2);

    fprintf('\n========== [Mode 3/5] LDPC (norm. min-sum) ==========\n');
    rng(cfg.rng_seed_base + 3, 'twister');
    r3 = run_fhbfsk_loop_ldpc(ldpc_codec, pset, cfg);
    [bler(3,:), ber(3,:), nframes(3,:), nerr_frame(3,:), nerr_bit(3,:)] = unpack(r3);

    fprintf('\n========== [Mode 4/5] Polar Fixed-SCL (L=%d) ==========\n', cfg.fec_polar_list_len);
    rng(cfg.rng_seed_base + 4, 'twister');
    r4 = run_fhbfsk_loop_janus(params_polar_fix, pset, cfg);
    [bler(4,:), ber(4,:), nframes(4,:), nerr_frame(4,:), nerr_bit(4,:)] = unpack(r4);

    fprintf('\n========== [Mode 5/5] Polar Adaptive-SCL (L0=%d->%d) ==========\n', ...
        cfg.fec_polar_adaptive_min_list, cfg.fec_polar_list_len);
    rng(cfg.rng_seed_base + 5, 'twister');
    r5 = run_fhbfsk_loop_janus(params_polar_adp, pset, cfg);
    [bler(5,:), ber(5,:), nframes(5,:), nerr_frame(5,:), nerr_bit(5,:)] = unpack(r5);

    %% ===== Phase 4: Wilson CI =====
    fprintf('\n[Phase 4] Computing Wilson 95%% CI ...\n');
    ci = compute_wilson_ci(bler, nframes, 0.95);

    %% ===== Phase 5: Coding gain =====
    fprintf('\n[Phase 5] Coding gain interpolation ...\n');
    gains = compute_coding_gains(cfg.ebn0_db, bler, cfg.target_bler);
    print_coding_gains(mode_names, gains, cfg.target_bler);

    %% ===== Phase 6: Figure =====
    fprintf('\n[Phase 6] Generating BLER figure ...\n');
    fig_path = generate_bler_figure(cfg.ebn0_db, bler, ci, mode_names, cfg);
    fprintf('  Saved: %s\n', fig_path);

    %% ===== Phase 7: Save =====
    mat_path = fullfile(cfg.asset_dir, 'fhbfsk_5fec_results.mat');
    fhbfsk_cfg = cfg;
    save(mat_path, 'bler', 'ber', 'nframes', 'nerr_frame', 'nerr_bit', ...
        'ci', 'gains', 'mode_names', 'fhbfsk_cfg');
    fprintf('  Saved: %s\n', mat_path);

    tex_path = generate_gain_table(gains, mode_names, cfg);
    fprintf('  Saved: %s\n', tex_path);

    %% ===== Output =====
    out.cfg        = cfg;
    out.mode_names = mode_names;
    out.ebn0_db    = cfg.ebn0_db;
    out.bler       = bler;
    out.ber        = ber;
    out.nframes    = nframes;
    out.ci         = ci;
    out.gains      = gains;
    out.files      = {fig_path, mat_path, tex_path};

    fprintf('\n############################################################\n');
    fprintf('#  5-FEC FH-BFSK CAMPAIGN DONE (%s)                       #\n', upper(cfg.channel_mode));
    fprintf('############################################################\n');
end

%% ========================================================================
%  FH-BFSK Waveform-Level Channel
%  ========================================================================

function y = apply_fhbfsk_channel(bband, ebn0_db, code_rate, pset, cfg)
%APPLY_FHBFSK_CHANNEL  Apply AWGN or UWA channel to FH-BFSK waveform.
    bband = bband(:);
    nsamp = length(bband);

    % Signal power
    P_sig = mean(abs(bband).^2);

    % Energy per coded bit (one chip carries one coded bit)
    chip_nsample = round(pset.chip_dur * cfg.bband_fs);
    E_s = P_sig * chip_nsample / cfg.bband_fs;  % energy per chip

    % Eb/N0 -> noise PSD
    E_b = E_s / code_rate;
    ebn0_lin = 10^(ebn0_db / 10);
    N0 = E_b / ebn0_lin;
    noise_var = N0 * cfg.bband_fs;   % complex noise variance per sample

    if strcmp(cfg.channel_mode, 'uwa')
        % Multipath at waveform sample level
        [h_samp, h_gains] = sample_uwa_taps_waveform(pset, cfg);
        y = conv(bband, h_samp(:));
        y = y(1:nsamp);

        % Recompute noise variance after channel (if normalized)
        if cfg.uwa_normalize_frame_power
            % Normalization is already applied inside sample_uwa_taps_waveform
            % Signal power changes, but Eb/N0 is defined at TX, so noise_var stays
        end

        % Background AWGN
        noise_bg = sqrt(noise_var/2) * (randn(nsamp,1) + 1i*randn(nsamp,1));

        % Impulsive noise
        imp_mask = rand(nsamp,1) < cfg.uwa_impulsive_prob;
        noise_imp = sqrt(noise_var/2 * cfg.uwa_impulsive_var_ratio) ...
                  .* (randn(nsamp,1) + 1i*randn(nsamp,1)) .* imp_mask;

        y = y + noise_bg + noise_imp;
    else
        % Pure AWGN
        noise = sqrt(noise_var/2) * (randn(nsamp,1) + 1i*randn(nsamp,1));
        y = bband + noise;
    end
end

function [h_samp, gains] = sample_uwa_taps_waveform(pset, cfg)
%SAMPLE_UWA_TAPS_WAVEFORM  Generate waveform-level channel impulse response.
%   Converts chip-level delays to sample-level delays.
    chip_nsample = round(pset.chip_dur * cfg.bband_fs);
    delays_chip  = cfg.uwa_tap_delays;
    p_lin = 10 .^ (cfg.uwa_tap_gains_db / 10);
    p_lin = p_lin / max(1e-12, sum(p_lin));
    ntap  = length(delays_chip);
    gains = zeros(1, ntap);

    switch cfg.uwa_fading
      case 'static'
        gains = sqrt(p_lin);
      case 'rayleigh'
        gains = sqrt(p_lin) .* randn(1, ntap);
      case 'rician'
        k_lin = 10^(cfg.uwa_k_factor_db / 10);
        if ntap >= 1
            gains(1) = sqrt(p_lin(1)) * (sqrt(k_lin/(k_lin+1)) + sqrt(1/(k_lin+1))*randn);
        end
        if ntap >= 2
            gains(2:end) = sqrt(p_lin(2:end)) .* randn(1, ntap-1);
        end
    end

    if cfg.uwa_normalize_frame_power
        pg = sum(gains.^2);
        if pg > 0, gains = gains / sqrt(pg); end
    end

    % Build sample-level impulse response
    sample_delays = round(delays_chip * chip_nsample);   % round() -> integer sample indices
    h_len = max(sample_delays) + 1;
    h_samp = zeros(h_len, 1);
    for k = 1:ntap
        h_samp(sample_delays(k) + 1) = gains(k);
    end
end

%% ========================================================================
%  FH-BFSK Simulation Loops
%  ========================================================================

function res = run_fhbfsk_loop_janus(params, pset, cfg)
% Conv / Polar via JANUS pipeline + FH-BFSK waveform.
    nsnr = length(cfg.ebn0_db);
    res  = init_result(nsnr);
    code_rate = cfg.K / cfg.E;

    for si = 1:nsnr
        fc=0; fe=0; be=0; bc=0;
        while fc < cfg.max_frames
            bits  = logical(randi([0 1], 1, cfg.K));
            coded = fec_encode_bits(bits, params);

            % FH-BFSK modulation -> channel -> demodulation
            bband = fhbfsk_mod(coded, pset, cfg.bband_fs);
            y     = apply_fhbfsk_channel(bband, cfg.ebn0_db(si), code_rate, pset, cfg);
            bp    = fhbfsk_demod(y, pset, cfg.bband_fs, cfg.E);

            dec_bits = fec_decode_soft_bits(bp, cfg.K, params);

            nerr = nnz(xor(bits, dec_bits));
            be=be+nerr; bc=bc+cfg.K; fe=fe+(nerr>0); fc=fc+1;
            if cfg.min_frame_errors>0 && fe>=cfg.min_frame_errors, break; end
        end
        res = store_snr(res, si, fc, fe, be, bc);
        print_progress(params.fec_mode, cfg.ebn0_db(si), res, si);
    end
end

function res = run_fhbfsk_loop_turbo(turbo_codec, pset, cfg)
% Turbo + JANUS interleaving + FH-BFSK waveform.
    nsnr = length(cfg.ebn0_db);
    res  = init_result(nsnr);
    code_rate = cfg.K / cfg.E;

    for si = 1:nsnr
        fc=0; fe=0; be=0; bc=0;
        while fc < cfg.max_frames
            bits  = logical(randi([0 1], 1, cfg.K));
            coded = turbo_encode_janus(bits, turbo_codec);
            [coded_ilv, q] = interleave(double(coded));

            bband = fhbfsk_mod(coded_ilv, pset, cfg.bband_fs);
            y     = apply_fhbfsk_channel(bband, cfg.ebn0_db(si), code_rate, pset, cfg);
            bp    = fhbfsk_demod(y, pset, cfg.bband_fs, cfg.E);

            % Convert bit_prob -> LLR for turbo decoder
            bp_clip = min(max(bp, 1e-6), 1-1e-6);
            llr = log((1 - bp_clip) ./ bp_clip);  % positive = bit 0

            % Deinterleave (llr_flip handled inside turbo_decode_janus)
            llr_dilv = deinterleave(llr(:)', q);

            dec_bits = turbo_decode_janus(llr_dilv, turbo_codec);

            nerr = sum(xor(bits, dec_bits(1:cfg.K)));
            be=be+nerr; bc=bc+cfg.K; fe=fe+(nerr>0); fc=fc+1;
            if cfg.min_frame_errors>0 && fe>=cfg.min_frame_errors, break; end
        end
        res = store_snr(res, si, fc, fe, be, bc);
        print_progress('Turbo', cfg.ebn0_db(si), res, si);
    end
end

function res = run_fhbfsk_loop_ldpc(ldpc_codec, pset, cfg)
% LDPC + JANUS interleaving + FH-BFSK waveform.
    nsnr = length(cfg.ebn0_db);
    res  = init_result(nsnr);
    code_rate = cfg.K / cfg.E;

    for si = 1:nsnr
        fc=0; fe=0; be=0; bc=0;
        while fc < cfg.max_frames
            bits  = logical(randi([0 1], 1, cfg.K));
            coded = ldpc_encode_janus(bits, ldpc_codec);
            [coded_ilv, q] = interleave(double(coded));

            bband = fhbfsk_mod(coded_ilv, pset, cfg.bband_fs);
            y     = apply_fhbfsk_channel(bband, cfg.ebn0_db(si), code_rate, pset, cfg);
            bp    = fhbfsk_demod(y, pset, cfg.bband_fs, cfg.E);

            bp_clip = min(max(bp, 1e-6), 1-1e-6);
            llr = log((1 - bp_clip) ./ bp_clip);

            % Deinterleave (llr_flip handled inside ldpc_decode_janus)
            llr_dilv = deinterleave(llr(:)', q);

            dec_bits = ldpc_decode_janus(llr_dilv, ldpc_codec);

            nerr = sum(xor(bits, dec_bits(1:cfg.K)));
            be=be+nerr; bc=bc+cfg.K; fe=fe+(nerr>0); fc=fc+1;
            if cfg.min_frame_errors>0 && fe>=cfg.min_frame_errors, break; end
        end
        res = store_snr(res, si, fc, fe, be, bc);
        print_progress('LDPC', cfg.ebn0_db(si), res, si);
    end
end

%% ========================================================================
%  LLR Sign Detection for Turbo/LDPC (via FH-BFSK round-trip)
%  ========================================================================

function turbo_codec = detect_llr_sign_turbo(turbo_codec, pset, cfg)
    bits  = logical(randi([0 1], 1, cfg.K));
    coded = turbo_encode_janus(bits, turbo_codec);
    [coded_ilv, q] = interleave(double(coded));

    bband = fhbfsk_mod(coded_ilv, pset, cfg.bband_fs);
    bp    = fhbfsk_demod(bband, pset, cfg.bband_fs, cfg.E);

    bp_clip = min(max(bp, 1e-6), 1-1e-6);
    llr = log((1 - bp_clip) ./ bp_clip);
    llr_dilv = deinterleave(llr(:)', q);

    dec_pos = turbo_decode_janus(llr_dilv, turbo_codec);
    err_pos = sum(xor(bits, dec_pos(1:cfg.K)));

    dec_neg = turbo_decode_janus(-llr_dilv, turbo_codec);
    err_neg = sum(xor(bits, dec_neg(1:cfg.K)));

    if err_pos == 0
        turbo_codec.llr_flip = false;
        fprintf('  Turbo LLR sign: normal\n');
    elseif err_neg == 0
        turbo_codec.llr_flip = true;
        fprintf('  Turbo LLR sign: FLIPPED\n');
    else
        error('Turbo decode fails with both LLR conventions (err: %d / %d)', err_pos, err_neg);
    end
end

function ldpc_codec = detect_llr_sign_ldpc(ldpc_codec, pset, cfg)
    bits  = logical(randi([0 1], 1, cfg.K));
    coded = ldpc_encode_janus(bits, ldpc_codec);
    [coded_ilv, q] = interleave(double(coded));

    bband = fhbfsk_mod(coded_ilv, pset, cfg.bband_fs);
    bp    = fhbfsk_demod(bband, pset, cfg.bband_fs, cfg.E);

    bp_clip = min(max(bp, 1e-6), 1-1e-6);
    llr = log((1 - bp_clip) ./ bp_clip);
    llr_dilv = deinterleave(llr(:)', q);

    dec_pos = ldpc_decode_janus(llr_dilv, ldpc_codec);
    err_pos = sum(xor(bits, dec_pos(1:cfg.K)));

    dec_neg = ldpc_decode_janus(-llr_dilv, ldpc_codec);
    err_neg = sum(xor(bits, dec_neg(1:cfg.K)));

    if err_pos == 0
        ldpc_codec.llr_flip = false;
        fprintf('  LDPC  LLR sign: normal\n');
    elseif err_neg == 0
        ldpc_codec.llr_flip = true;
        fprintf('  LDPC  LLR sign: FLIPPED\n');
    else
        error('LDPC decode fails with both LLR conventions (err: %d / %d)', err_pos, err_neg);
    end
end

%% ========================================================================
%  Result Helpers (same as run_5fec_uwa_campaign)
%  ========================================================================

function res = init_result(nsnr)
    res.bler=zeros(1,nsnr); res.ber=zeros(1,nsnr);
    res.nframes=zeros(1,nsnr); res.nerr_frame=zeros(1,nsnr); res.nerr_bit=zeros(1,nsnr);
end

function res = store_snr(res, si, fc, fe, be, bc)
    res.nframes(si)=fc; res.nerr_frame(si)=fe; res.nerr_bit(si)=be;
    res.bler(si)=fe/max(1,fc); res.ber(si)=be/max(1,bc);
end

function [bl,br,nf,nfe,nbe] = unpack(res)
    bl=res.bler; br=res.ber; nf=res.nframes; nfe=res.nerr_frame; nbe=res.nerr_bit;
end

function print_progress(mode_name, ebn0, res, si)
    fprintf('  %s  Eb/N0=%5.2f dB | frames=%6d | BLER=%.4e | BER=%.4e\n', ...
        mode_name, ebn0, res.nframes(si), res.bler(si), res.ber(si));
end

%% ========================================================================
%  Wilson CI / Coding Gain / Figure / Table (same as run_5fec_uwa_campaign)
%  ========================================================================

function ci = compute_wilson_ci(bler, nframes, conf_level)
    z=norminv(0.5+conf_level/2); n=max(1,nframes); p=bler;
    den=1+(z^2)./n; center=(p+(z^2)./(2*n))./den;
    half=(z./den).*sqrt((p.*(1-p))./n+(z^2)./(4*n.^2));
    ci.center=center; ci.half_width=half;
    ci.lower=max(0,center-half); ci.upper=min(1,center+half);
end

function gains = compute_coding_gains(ebn0_db, bler, target_bler)
    nmodes=size(bler,1); ntarget=length(target_bler);
    snr_at_target=nan(nmodes,ntarget);
    for mi=1:nmodes, for ti=1:ntarget
        snr_at_target(mi,ti)=interp_snr_at_bler(ebn0_db,bler(mi,:),target_bler(ti));
    end, end
    gains.target_bler=target_bler; gains.snr_at_target=snr_at_target;
    gains.coding_gain=nan(nmodes,ntarget);
    for mi=1:nmodes, gains.coding_gain(mi,:)=snr_at_target(1,:)-snr_at_target(mi,:); end
end

function snr = interp_snr_at_bler(ebn0_db, bler_vec, target)
    snr=NaN; lb=log10(max(bler_vec,1e-12)); lt=log10(target);
    for i=1:(length(lb)-1)
        if (lb(i)>=lt && lb(i+1)<=lt)||(lb(i)<=lt && lb(i+1)>=lt)
            frac=(lt-lb(i))/(lb(i+1)-lb(i));
            snr=ebn0_db(i)+frac*(ebn0_db(i+1)-ebn0_db(i)); return;
        end
    end
end

function print_coding_gains(mode_names, gains, target_bler)
    fprintf('\n  Coding Gains vs Conv:\n');
    fprintf('  %-28s','');
    for ti=1:length(target_bler), fprintf('  BLER=%.0e',target_bler(ti)); end
    fprintf('\n');
    for mi=1:length(mode_names)
        fprintf('  %-28s',mode_names{mi});
        for ti=1:length(target_bler)
            g=gains.coding_gain(mi,ti);
            if isnan(g), fprintf('  %9s','N/A'); else, fprintf('  %+7.2f dB',g); end
        end
        fprintf('\n');
    end
end

function fig_path = generate_bler_figure(ebn0_db, bler, ci, mode_names, cfg)
    markers={'o-','s-','d-','^-','v-'}; colors=lines(5);
    f=figure('Visible','off','Position',[100 100 720 540]);
    for mi=1:size(bler,1)
        valid=bler(mi,:)>0;
        if any(valid)
            x_fill=[ebn0_db(valid),fliplr(ebn0_db(valid))];
            y_fill=[ci.upper(mi,valid),fliplr(ci.lower(mi,valid))];
            y_fill=max(y_fill,1e-5);
            fill(x_fill,y_fill,colors(mi,:),'FaceAlpha',0.15,'EdgeColor','none'); hold on;
        end
    end
    for mi=1:size(bler,1)
        valid=bler(mi,:)>0;
        semilogy(ebn0_db(valid),bler(mi,valid),markers{mi},...
            'Color',colors(mi,:),'LineWidth',1.4,'MarkerSize',5); hold on;
    end
    for tgt=cfg.target_bler
        yline(tgt,'--',sprintf('BLER=10^{%.0f}',log10(tgt)),...
            'Color',[0.5 0.5 0.5],'Alpha',0.6,'LabelHorizontalAlignment','left');
    end
    grid on; set(gca,'YScale','log');
    xlabel('E_b/N_0 (dB)'); ylabel('BLER');
    ch_label = upper(cfg.channel_mode);
    title(sprintf('%s FH-BFSK 5-FEC BLER (K=%d, E=%d, 95%% Wilson CI)', ch_label, cfg.K, cfg.E));
    legend(mode_names,'Location','southwest','FontSize',8); ylim([1e-4,1]);
    fig_path = fullfile(cfg.asset_dir, sprintf('fhbfsk_%s_5fec_bler_ci.png', cfg.channel_mode));
    exportgraphics(f, fig_path, 'Resolution', 300); close(f);
end

function tex_path = generate_gain_table(gains, mode_names, cfg)
    tex_path = fullfile(cfg.asset_dir, sprintf('fhbfsk_%s_5fec_coding_gain.tex', cfg.channel_mode));
    fid=fopen(tex_path,'w');
    fprintf(fid,'%% Auto-generated by run_5fec_fhbfsk_campaign.m (%s)\n', cfg.channel_mode);
    fprintf(fid,'\\begin{table}[t]\n\\centering\n');
    fprintf(fid,'\\caption{%s FH-BFSK coding gain (Conv baseline, K=%d, E=%d).}\n', ...
        upper(cfg.channel_mode), cfg.K, cfg.E);
    fprintf(fid,'\\small\n');
    nt=length(gains.target_bler);
    fprintf(fid,'\\begin{tabular*}{\\columnwidth}{@{\\extracolsep{\\fill}} l%s c}\n', repmat(' c',1,nt));
    fprintf(fid,'\\toprule\nFEC');
    for ti=1:nt, fprintf(fid,' & $E_b/N_0$ at $10^{%.0f}$',log10(gains.target_bler(ti))); end
    fprintf(fid,' & $G_{\\text{max}}$ \\\\\n\\midrule\n');
    short_names={'Conv','Turbo','LDPC','Polar (fix)','Polar (adp)'};
    for mi=1:length(mode_names)
        fprintf(fid,'%s',short_names{mi});
        for ti=1:nt
            v=gains.snr_at_target(mi,ti);
            if isnan(v), fprintf(fid,' & N/A'); else, fprintf(fid,' & %.1f',v); end
        end
        g=gains.coding_gain(mi,:); gv=g(~isnan(g));
        if isempty(gv), fprintf(fid,' & N/A'); else, fprintf(fid,' & %.1f',max(gv)); end
        fprintf(fid,' \\\\\n');
    end
    fprintf(fid,'\\bottomrule\n\\end{tabular*}\n\\end{table}\n');
    fclose(fid);
end

%% ========================================================================
%  Defaults
%  ========================================================================

function cfg = fill_defaults(cfg)
    if ~isfield(cfg,'K'),               cfg.K = 64;              end
    if ~isfield(cfg,'E'),               cfg.E = 144;             end
    if ~isfield(cfg,'channel_mode'),    cfg.channel_mode = 'awgn'; end
    if ~isfield(cfg,'bband_fs'),        cfg.bband_fs = 44100;    end
    if ~isfield(cfg,'ebn0_db')
        if strcmp(cfg.channel_mode,'awgn')
            cfg.ebn0_db = 0:0.5:12;
        else
            cfg.ebn0_db = 0:0.5:16;
        end
    end
    if ~isfield(cfg,'max_frames'),      cfg.max_frames = 10000;  end
    if ~isfield(cfg,'min_frame_errors'), cfg.min_frame_errors = 300; end
    if ~isfield(cfg,'rng_seed_base'),   cfg.rng_seed_base = 42;  end
    if ~isfield(cfg,'sanity_trials'),   cfg.sanity_trials = 10;  end
    if ~isfield(cfg,'target_bler'),     cfg.target_bler = [1e-1, 1e-2]; end

    % Polar
    if ~isfield(cfg,'fec_polar_list_len'),         cfg.fec_polar_list_len = 8;     end
    if ~isfield(cfg,'fec_polar_crc_len'),          cfg.fec_polar_crc_len = 11;     end
    if ~isfield(cfg,'fec_polar_reliability_method'), cfg.fec_polar_reliability_method = 'ga'; end
    if ~isfield(cfg,'fec_polar_design_ebn0_db'),   cfg.fec_polar_design_ebn0_db = 2.0; end
    if ~isfield(cfg,'fec_polar_adaptive_min_list'), cfg.fec_polar_adaptive_min_list = 4; end

    % UWA channel
    if ~isfield(cfg,'uwa_tap_delays'),        cfg.uwa_tap_delays = [0 1 3];      end
    if ~isfield(cfg,'uwa_tap_gains_db'),      cfg.uwa_tap_gains_db = [0 -6 -10]; end
    if ~isfield(cfg,'uwa_fading'),            cfg.uwa_fading = 'rician';          end
    if ~isfield(cfg,'uwa_k_factor_db'),       cfg.uwa_k_factor_db = 6;           end
    if ~isfield(cfg,'uwa_normalize_frame_power'), cfg.uwa_normalize_frame_power = 1; end
    if ~isfield(cfg,'uwa_impulsive_prob'),    cfg.uwa_impulsive_prob = 0.01;      end
    if ~isfield(cfg,'uwa_impulsive_var_ratio'), cfg.uwa_impulsive_var_ratio = 25; end

    % Output
    if ~isfield(cfg,'asset_dir')
        cfg.asset_dir = fullfile(fileparts(mfilename('fullpath')), ...
            '..', 'data', sprintf('fhbfsk_%s', cfg.channel_mode));
    end
end

function ensure_dir(d)
    if ~exist(d,'dir'), mkdir(d); end
end
