function janus_root = setup_paths(janus_root)
%SETUP_PATHS  Put this repository and the janus-m 3.0.5 tree on the MATLAB path.
%
%   The simulation chain is a *patch* on top of the CMRE janus-m 3.0.5
%   reference implementation, which is not redistributed here (see NOTICE.md).
%   Download it first, then:
%
%     setup_paths('C:\path\to\janus-m-3.0.5')
%
%   The path order matters: src/janus_patched must shadow the upstream
%   tx.m / rx.m / demod.m / parameters.m / defaults.m.
%
%   With no argument, the environment variable JANUS_M_ROOT is used.

    repo = fileparts(mfilename('fullpath'));

    if nargin < 1 || isempty(janus_root)
        janus_root = getenv('JANUS_M_ROOT');
    end
    if isempty(janus_root)
        error('setup_paths:noJanusRoot', ...
            ['janus-m 3.0.5 root not given. Call setup_paths(''<path>'') ' ...
             'or set the JANUS_M_ROOT environment variable.']);
    end
    if ~exist(fullfile(janus_root, 'pset_new.m'), 'file')
        error('setup_paths:badJanusRoot', ...
            '"%s" does not look like a janus-m 3.0.5 tree (pset_new.m missing).', janus_root);
    end

    % Upstream first, then our overrides on top.
    addpath(janus_root);
    addpath(fullfile(janus_root, 'plugins'));
    addpath(fullfile(repo, 'src', 'janus_patched'));
    addpath(fullfile(repo, 'src', 'phy'));
    addpath(fullfile(repo, 'src', 'fec'));
    addpath(fullfile(repo, 'experiments'));
    % analysis/ is matplotlib, not MATLAB — nothing to add to the path.

    clear functions; %#ok<CLFUNC>  % drop cached copies of shadowed upstream files
    rehash;

    fprintf('janus-fec-oceans2026 paths set.\n');
    fprintf('  repo       : %s\n', repo);
    fprintf('  janus-m    : %s\n', janus_root);
    fprintf('  toolboxes  : Communications%s, Signal Processing%s\n', ...
        tick(license('test', 'Communication_Toolbox')), ...
        tick(license('test', 'Signal_Toolbox')));
end

function s = tick(ok)
    if ok, s = ' [ok]'; else, s = ' [MISSING]'; end
end
