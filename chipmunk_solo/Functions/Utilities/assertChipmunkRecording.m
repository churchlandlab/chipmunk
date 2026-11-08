function assertChipmunkRecording()
% Fail at a trial boundary before delivering more stimuli without ephys data.
global BpodSystem
if ~ephysRecordingEnabled(BpodSystem.ProtocolSettings),return;end
s=spikeglx_client('refresh');
if s.connected && s.running && s.recording && s.ownedRun && ~s.startPending,return;end
message=['Ephys recording is no longer confirmed; session stopped. ' s.lastError];
BpodSystem.Data.EphysRecordingFailure=struct('time',datestr(now,30),'message',message);
spikeglx_client('log',message);
error('chipmunk_solo:RecordingLost','%s',message);
end
