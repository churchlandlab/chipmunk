function ensureOptionalRecordingSettings()
% SpikeGLX stays off unless the operator fills the host at startup.
global BpodSystem
if ~isfield(BpodSystem.ProtocolSettings, 'spikeGLXHost')
    BpodSystem.ProtocolSettings.spikeGLXHost = '';
end
end
