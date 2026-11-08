function half_second_chipmunk_ephys(varargin)
% Preserve the ephys launcher while using the unified solo task and GUI.
global BpodSystem
root = fullfile(BpodSystem.Path.ProtocolFolder,'chipmunk_solo');
assert(isfile(fullfile(root,'chipmunk_solo.m')), ...
    'chipmunk_solo:MissingProtocol','Install the sibling chipmunk_solo protocol first.');
if ~isfield(BpodSystem.ProtocolSettings,'spikeGLXHost') || ...
        isempty(strtrim(BpodSystem.ProtocolSettings.spikeGLXHost))
    BpodSystem.ProtocolSettings.spikeGLXHost = 'jupiter.local';
end
addpath(root);
chipmunk_solo(varargin{:});
end
