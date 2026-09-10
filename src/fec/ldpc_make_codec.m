function codec = ldpc_make_codec()
%LDPC_MAKE_CODEC  Build LDPC encoder/decoder config for (144,64) code.
%
%   codec = ldpc_make_codec()
%
%   Returns a struct with:
%     .enc_cfg   : ldpcEncoderConfig object
%     .dec_cfg   : ldpcDecoderConfig object
%     .H         : sparse logical 80x144 parity-check matrix
%     .K         : 64
%     .E         : 144
%     .max_iter  : 50

    K = 64;
    E = 144;
    max_iter = 50;

    % Build parity-check matrix and convert to sparse logical
    [H, h_cfg] = build_ldpc_matrix_144_64();
    H = sparse(logical(H));

    % Encoder config
    enc_cfg = ldpcEncoderConfig(H);

    % Decoder config
    dec_cfg = ldpcDecoderConfig(H);
    % Set algorithm — use try/catch to handle API differences across versions
    try
        dec_cfg.Algorithm = 'norm-min-sum';
    catch
        try
            dec_cfg.Algorithm = 'Normalized min-sum';
        catch
            warning('LDPC:Algorithm', 'Could not set norm-min-sum, using default algorithm');
        end
    end

    % Package
    codec.enc_cfg  = enc_cfg;
    codec.dec_cfg  = dec_cfg;
    codec.H        = H;
    codec.K        = K;
    codec.E        = E;
    codec.max_iter = max_iter;
    codec.h_cfg    = h_cfg;
end
