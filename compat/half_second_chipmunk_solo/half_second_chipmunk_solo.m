function half_second_chipmunk_solo(varargin)
% Preserve existing Bpod protocol/settings selections on the unified runner.
global BpodSystem
root = fullfile(BpodSystem.Path.ProtocolFolder,'chipmunk_solo');
assert(isfile(fullfile(root,'chipmunk_solo.m')), ...
    'chipmunk_solo:MissingProtocol','Install the sibling chipmunk_solo protocol first.');
addpath(root);
chipmunk_solo(varargin{:});
end
