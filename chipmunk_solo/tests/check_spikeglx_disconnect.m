function check_spikeglx_disconnect()
% A dead server must not be contacted again by the GUI's refresh/trace loop.
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
ChipmunkSpikeGLTest.pollFailure=true;
s=spikeglx_client('refresh');assert(~s.connected && contains(s.lastError,'lost'));
polls=ChipmunkSpikeGLTest.polls;
for k=1:5
    spikeglx_client('refresh');traces=spikeglx_client('traces');assert(~traces.ok);
end
assert(ChipmunkSpikeGLTest.polls==polls,'Disconnected GUI keeps polling the dead server');
assert(ChipmunkSpikeGLTest.closes==1,'Failed connection was not closed');
ChipmunkSpikeGLTest.pollFailure=false;
s=spikeglx_client('connect');assert(s.connected,'Explicit reconnect failed');
spikeglx_client('shutdown');
fprintf('PASS: dead connection closed, background retries stopped, explicit reconnect works\n');
end
function restore(oldPath,oldServer,prefs,hadPrefs,original)
global ChipmunkSpikeGLTest
clear spikeglx_client
ChipmunkSpikeGLTest=oldServer;path(oldPath);
if hadPrefs,fid=fopen(prefs,'w');fwrite(fid,original,'uint8');fclose(fid);
elseif isfile(prefs),delete(prefs);end
end
