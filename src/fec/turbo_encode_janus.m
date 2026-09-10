function [coded, info] = turbo_encode_janus(bits, enc_obj)
%TURBO_ENCODE_JANUS  LTE-style rate-1/3 turbo encode with puncturing to E=144.
%
%   [coded, info] = turbo_encode_janus(bits)
%   [coded, info] = turbo_encode_janus(bits, enc_obj)
%
%   bits    : 1xK logical/double row vector (K=64)
%   enc_obj : (optional) pre-built encoder struct from turbo_make_codec()
%   coded   : 1xE double row vector (E=144)
%   info    : struct with encoding metadata

    if nargin < 2 || isempty(enc_obj)
        persistent cached_enc;
        if isempty(cached_enc)
            cached_enc = turbo_make_codec();
        end
        enc_obj = cached_enc;
    end

    K = enc_obj.K;
    assert(numel(bits) == K, 'Input must be %d bits', K);

    % Encode: mother codeword (204 bits for K=64, CL=4)
    mother = enc_obj.encoder(bits(:));

    % Puncture to E=144
    coded = double(mother(enc_obj.punct_mask)).';

    info.K = K;
    info.E = enc_obj.E;
    info.mother_len = length(mother);
    info.code_rate = K / enc_obj.E;
end
