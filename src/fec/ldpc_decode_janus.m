function [dec_bits, info] = ldpc_decode_janus(llr, dec_obj)
%LDPC_DECODE_JANUS  LDPC decode E=144 LLRs to K=64 bits.
%
%   [dec_bits, info] = ldpc_decode_janus(llr)
%   [dec_bits, info] = ldpc_decode_janus(llr, dec_obj)
%
%   llr      : 1xE or Ex1 double (E=144), convention: positive = bit 0
%   dec_obj  : (optional) pre-built struct from ldpc_make_codec()
%   dec_bits : 1xK logical row vector (K=64)

    if nargin < 2 || isempty(dec_obj)
        persistent cached_dec;
        if isempty(cached_dec)
            cached_dec = ldpc_make_codec();
        end
        dec_obj = cached_dec;
    end

    E = dec_obj.E;
    K = dec_obj.K;
    assert(numel(llr) == E, 'Input LLR must be %d elements', E);

    % Flip LLR sign if needed
    llr_in = double(llr(:));
    if isfield(dec_obj, 'llr_flip') && dec_obj.llr_flip
        llr_in = -llr_in;
    end

    % LDPC decode
    [decoded, act_iter, final_pc] = ldpcDecode(llr_in, dec_obj.dec_cfg, dec_obj.max_iter);

    % ldpcDecode may return K info bits or full N codeword
    if numel(decoded) == K
        dec_bits = logical(decoded(:)).';
    elseif isfield(dec_obj, 'info_indices') && ~isempty(dec_obj.info_indices)
        dec_bits = logical(decoded(dec_obj.info_indices)).';
    else
        dec_bits = logical(decoded(1:K)).';
    end

    info.K = K;
    info.E = E;
    info.actual_iterations = act_iter;
    info.parity_checks_satisfied = all(final_pc == 0);
end
