function [ready, message] = beginChipmunkRecording()
% Trials may begin only after this session's recording is confirmed active.
global BpodSystem
ready = true;
message = '';
if ~ephysRecordingEnabled(BpodSystem.ProtocolSettings)
    return
end
state = spikeglx_client('begin');
ready = state.connected && state.running && state.recording && ...
    state.ownedRun && strcmp(state.remoteRunName,state.runName) && isempty(state.lastError);
if ready
    [ready,message]=labcams_ephys('start');
    if ~ready
        spikeglx_client('disable');
        spikeglx_client('set','lastError',message);spikeglx_client('log',message);
        return
    end
    BpodSystem.Data.EphysRecording=struct('host',state.host,'directory',state.sessionDir,'runName',state.runName);
    BpodSystem.Data.EphysAnatomy=struct('applied',state.anatomyApplied, ...
        'status',state.anatomyStatus,'provenance',state.anatomyProvenance);
else
    message = state.lastError;
end
end
