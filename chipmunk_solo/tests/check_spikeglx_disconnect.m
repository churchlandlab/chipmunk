function check_spikeglx_disconnect()
% Recover an idle connection once; a dead server must not be polled repeatedly.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path;global ChipmunkSpikeGLTest
oldServer=ChipmunkSpikeGLTest;
prefs=fullfile(root,'spikeglx_prefs.mat');hadPrefs=isfile(prefs);original=[];
if hadPrefs,fid=fopen(prefs,'r');original=fread(fid,Inf,'*uint8');fclose(fid);end
cleanup=onCleanup(@() restore(oldPath,oldServer,prefs,hadPrefs,original));
addpath(fullfile(root,'Functions'));addpath(fullfile(root,'tests','fixtures','spikeglx'));
clear spikeglx_client
ChipmunkSpikeGLTest=struct('connectFailure',false,'dataDir','test-data', ...
    'running',false,'saving',false,'targetSaving',false,'pending',0,'runName','', ...
    'pollFailure',false,'polls',0,'closes',0);
s=spikeglx_client('connect');assert(s.connected,'%s',s.lastError);
% Only the control socket expires; acquisition remains active on the server.
spikeglx_client('set','runName','ephys');
spikeglx_client('set','sessionDir','test-data');
spikeglx_client('set','ownedRun',true);
ChipmunkSpikeGLTest.runName='ephys';
ChipmunkSpikeGLTest.running=true;
ChipmunkSpikeGLTest.saving=true;ChipmunkSpikeGLTest.targetSaving=true;
ChipmunkSpikeGLTest.expired=true;
s=spikeglx_client('refresh');
assert(s.connected && s.running && s.recording && s.ownedRun && isempty(s.lastError));
assert(any(contains(s.actionLog,'Control connection restored')));
ChipmunkSpikeGLTest.expired=true;
traces=spikeglx_client('traces');s=spikeglx_client('get');
assert(s.connected && s.recording && s.ownedRun,'Trace poll did not recover idle socket');
% Reconnection must recheck ownership and never infer that recording continued.
ChipmunkSpikeGLTest.runName='external';ChipmunkSpikeGLTest.expired=true;
s=spikeglx_client('refresh');assert(s.connected && ~s.ownedRun);
ChipmunkSpikeGLTest.running=false;ChipmunkSpikeGLTest.targetSaving=false;
ChipmunkSpikeGLTest.expired=true;
s=spikeglx_client('refresh');assert(s.connected && ~s.running && ~s.recording);
closes=ChipmunkSpikeGLTest.closes;
ChipmunkSpikeGLTest.pollFailure=true;
s=spikeglx_client('refresh');assert(~s.connected && contains(s.lastError,'lost'));
polls=ChipmunkSpikeGLTest.polls;
for k=1:5
    spikeglx_client('refresh');traces=spikeglx_client('traces');assert(~traces.ok);
end
assert(ChipmunkSpikeGLTest.polls==polls,'Disconnected GUI keeps polling the dead server');
assert(ChipmunkSpikeGLTest.closes==closes+2,'Failed connection was not closed');
ChipmunkSpikeGLTest.pollFailure=false;
s=spikeglx_client('connect');assert(s.connected,'Explicit reconnect failed');
spikeglx_client('shutdown');
fprintf('PASS: idle socket recovered, status and ownership rechecked, dead-server retries bounded\n');
end
function restore(oldPath,oldServer,prefs,hadPrefs,original)
global ChipmunkSpikeGLTest
clear spikeglx_client
ChipmunkSpikeGLTest=oldServer;path(oldPath);
if hadPrefs,fid=fopen(prefs,'w');fwrite(fid,original,'uint8');fclose(fid);
elseif isfile(prefs),delete(prefs);end
end
