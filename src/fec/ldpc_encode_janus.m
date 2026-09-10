function [coded, info] = ldpc_encode_janus(bits, enc_obj)
%LDPC_ENCODE_JANUS  LDPC encode K=64 bits to E=144 coded bits.
%
%   [coded, info] = ldpc_encode_janus(bits)
%   [coded, info] = ldpc_encode_janus(bits, enc_obj)
%
%   bits    : 1xK logical/double row vector (K=64)
%   enc_obj : (optional) pre-built struct from ldpc_make_codec()
%   coded   : 1xE double row vector (E=144)
%   info    : struct with encoding metadata

    if nargin < 2 || isempty(enc_obj)
        persistent cached_enc;
        if isempty(cached_enc)
            cached_enc = ldpc_make_codec();
        end
        enc_obj = cached_enc;
    end

    K = enc_obj.K;
    assert(numel(bits) == K, 'Input must be %d bits', K);

    % LDPC encode
    codeword = ldpcEncode(logical(bits(:)), enc_obj.enc_cfg);

    coded = double(codeword).';

    info.K = K;
    info.E = enc_obj.E;
    info.code_rate = K / enc_obj.E;
end
