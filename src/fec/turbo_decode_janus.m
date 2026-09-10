function [dec_bits, info] = turbo_decode_janus(llr, dec_obj)
%TURBO_DECODE_JANUS  Turbo decode E=144 LLRs to K=64 bits.
%
%   [dec_bits, info] = turbo_decode_janus(llr)
%   [dec_bits, info] = turbo_decode_janus(llr, dec_obj)
%
%   llr      : 1xE or Ex1 double (E=144), convention: positive = bit 0
%   dec_obj  : (optional) pre-built decoder struct from turbo_make_codec()
%   dec_bits : 1xK logical row vector (K=64)
%   info     : struct with decoding metadata

    if nargin < 2 || isempty(dec_obj)
        persistent cached_dec;
        if isempty(cached_dec)
            cached_dec = turbo_make_codec();
        end
        dec_obj = cached_dec;
    end

    E = dec_obj.E;
    assert(numel(llr) == E, 'Input LLR must be %d elements', E);

    % Flip LLR sign if sanity check determined it's needed
    llr_in = double(llr(:));
    if isfield(dec_obj, 'llr_flip') && dec_obj.llr_flip
        llr_in = -llr_in;
    end

    % De-puncture: insert zeros (erasures) at punctured positions
    llr_mother = zeros(dec_obj.mother_len, 1);
    llr_mother(dec_obj.punct_mask) = llr_in;

    % Turbo decode
    dec_raw = dec_obj.decoder(llr_mother);

    dec_bits = logical(dec_raw(1:dec_obj.K)).';

    info.K = dec_obj.K;
    info.E = E;
    info.num_iterations = dec_obj.num_iterations;
end
