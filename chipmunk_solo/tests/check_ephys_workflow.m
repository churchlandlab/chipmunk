function check_ephys_workflow()
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path;global BpodSystem ChipmunkSpikeGLTest
oldBpod=BpodSystem;oldServer=ChipmunkSpikeGLTest;
prefs=fullfile(root,'spikeglx_prefs.mat');hadPrefs=isfile(prefs);original=[];
if hadPrefs,fid=fopen(prefs,'r');original=fread(fid,Inf,'*uint8');fclose(fid);end
cleanup=onCleanup(@() restore(oldPath,oldBpod,oldServer,prefs,hadPrefs,original));
addpath(genpath(fullfile(root,'Functions')));addpath(fullfile(root,'tests','fixtures','spikeglx'));
clear spikeglx_client
resetServer();
s=spikeglx_client('begin');assert(~s.running && contains(s.lastError,'Prepare'));
s=spikeglx_client('prepare');assert(s.running && ~s.recording && s.ownedRun,'%s',s.lastError);
s=spikeglx_client('prepare');assert(ChipmunkSpikeGLTest.starts==1);
s=spikeglx_client('begin');assert(s.running && s.recording,'%s',s.lastError);
assert(any(contains(s.actionLog,'Prepared: acquisition ON; recording OFF')));
assert(contains(s.actionLog{end},'Recording confirmed'));
count=numel(s.actionLog);spikeglx_client('refresh');s=spikeglx_client('get');assert(numel(s.actionLog)==count);
assert(ChipmunkSpikeGLTest.enables==1);
s=spikeglx_client('begin');assert(s.recording && ChipmunkSpikeGLTest.enables==1);
spikeglx_client('shutdown');assert(~ChipmunkSpikeGLTest.running && ChipmunkSpikeGLTest.stops==1);

% Prepare verifies the checked devices every time, even if SpikeGLX still holds an older match.
resetServer();spikeglx_client('set','devices','');
s=spikeglx_client('prepare');assert(~s.running && contains(s.lastError,'at least one'));
ChipmunkSpikeGLTest.devices='(20,1,1)(20,obx)';spikeglx_client('set','devices','(20,1,1)(20,obx)');
s=spikeglx_client('prepare');assert(s.running && ChipmunkSpikeGLTest.detects==1,'%s',s.lastError);
spikeglx_client('shutdown');
% Probe moved to port 2 on a fresh SpikeGLX: checking port 2 is enough.
resetServer();ChipmunkSpikeGLTest.validated=false;ChipmunkSpikeGLTest.attached='(20,2,1)(20,obx)';
ChipmunkSpikeGLTest.devices='(20,1,1)(20,obx)';
spikeglx_client('set','devices','(20,1,1)(20,obx)');
s=spikeglx_client('prepare');assert(~s.running && contains(s.lastError,'not ready'));
spikeglx_client('set','devices','(20,2,1)(20,obx)');
s=spikeglx_client('prepare');assert(s.running && strcmp(ChipmunkSpikeGLTest.devices,'(20,2,1)(20,obx)'),'%s',s.lastError);
spikeglx_client('shutdown');
resetServer();ChipmunkSpikeGLTest.runName='previous';ChipmunkSpikeGLTest.existingNames={'previous'};
spikeglx_client('set','devices','(20,obx)');
s=spikeglx_client('prepare');assert(s.running && strcmp(s.remoteRunName,'FakeSubject_workflow'),'%s',s.lastError);
spikeglx_client('shutdown');
resetServer();ChipmunkSpikeGLTest.detectFailure=true;
spikeglx_client('set','devices','(20,obx)');
s=spikeglx_client('prepare');assert(~s.running && contains(s.lastError,'detection failed'),'%s',s.lastError);
resetServer();ChipmunkSpikeGLTest.startFailure=true;
s=spikeglx_client('prepare');assert(~s.running && ~s.ownedRun);
resetServer();ChipmunkSpikeGLTest.connectFailure=true;
s=spikeglx_client('prepare');assert(~s.connected && contains(s.lastError,'unavailable'));

resetServer();ChipmunkSpikeGLTest.running=true;ChipmunkSpikeGLTest.saving=true;
ChipmunkSpikeGLTest.targetSaving=true;ChipmunkSpikeGLTest.runName='OtherSession';
s=spikeglx_client('prepare');assert(s.running && contains(s.lastError,'Another'));
s=spikeglx_client('begin');assert(contains(s.lastError,'not prepared'));
s=spikeglx_client('enable');assert(contains(s.lastError,'does not own'));
s=spikeglx_client('stop');assert(contains(s.lastError,'does not own'));
spikeglx_client('shutdown');assert(ChipmunkSpikeGLTest.running && ChipmunkSpikeGLTest.saving);
assert(ChipmunkSpikeGLTest.stops==0 && ChipmunkSpikeGLTest.enables==0);

resetServer();ChipmunkSpikeGLTest.startSaves=true;
s=spikeglx_client('prepare');assert(s.running && ~s.recording);
spikeglx_client('shutdown');

resetServer();
dataRoot=tempname;mkdir(dataRoot);directoryCleanup=onCleanup(@() rmdir(dataRoot,'s'));
spikeglx_client('init','ephys','FakeSubject','20261102_120000');
spikeglx_client('set','host','localhost');spikeglx_client('set','dataDir',dataRoot);
s=spikeglx_client('prepare');
expected=[strrep(dataRoot,'\','/') '/FakeSubject/20261102_120000'];
assert(s.running && ~s.recording && strcmp(s.sessionDir,expected) && isfolder(expected),'%s',s.lastError);
assert(strcmp(ChipmunkSpikeGLTest.dataDir,expected));
assert(strcmp(ChipmunkSpikeGLTest.runName,'ephys'));
spikeglx_client('set','dataDir',dataRoot);s=spikeglx_client('get');assert(strcmp(s.sessionDir,expected));
% Another session can share the basename but must never inherit ownership.
ChipmunkSpikeGLTest.dataDir=[strrep(dataRoot,'\','/') '/OtherSubject/20261102_120001'];
s=spikeglx_client('begin');assert(~s.ownedRun && contains(s.lastError,'not prepared'));
stops=ChipmunkSpikeGLTest.stops;s=spikeglx_client('stop');
assert(ChipmunkSpikeGLTest.running && ChipmunkSpikeGLTest.stops==stops);
spikeglx_client('shutdown');assert(ChipmunkSpikeGLTest.running);
for invalid={'../FakeSubject','FakeSubject/other'}
 try,ensureSpikeGLXSessionFolder(dataRoot,invalid{1},'20261102_120000','localhost');error('Test:Accepted','Unsafe subject accepted');
 catch e,assert(~strcmp(e.identifier,'Test:Accepted'));end
end
clear directoryCleanup

resetServer();
spikeglx_client('init','FakeSubject_20261102_120000','FakeSubject','20261102_120000');
spikeglx_client('set','host','localhost');spikeglx_client('set','dataDir',tempname);
s=spikeglx_client('prepare');assert(~s.running && ChipmunkSpikeGLTest.starts==0 && contains(s.lastError,'root does not exist'));
assert(contains(s.actionLog{end},'prepare failed'));

resetServer();
BpodSystem=struct('ProtocolSettings',struct('spikeGLXHost','unit-test'),'PluginObjects',struct());
[ok,message]=beginChipmunkRecording();assert(~ok && contains(message,'Prepare'));
s=spikeglx_client('prepare');[ok,message]=beginChipmunkRecording();assert(ok && isempty(message));
BpodSystem.ProtocolSettings.spikeGLXHost='';[ok,message]=beginChipmunkRecording();assert(ok);
spikeglx_client('shutdown');
resetServer();
folder=tempname;mkdir(folder);folderCleanup=onCleanup(@() rmdir(folder,'s'));
region=struct('startUm',0,'endUm',100,'region','TEST','rgb',[10 20 30]);
profile=struct('formatVersion',1,'subject','FakeSubject','placementKind','surgery plan', ...
 'nShanks',4,'provenance',struct('sourceFile','synthetic.json','sourceSHA256',repmat('a',1,64)),'shanks',[]);
for k=1:4,profile.shanks(k).shankId=k-1;profile.shanks(k).segments=region;end
fid=fopen(fullfile(folder,'FakeSubject.json'),'w');fwrite(fid,jsonencode(profile));fclose(fid);
spikeglx_client('init','FakeSubject_workflow','FakeSubject');
spikeglx_client('set','anatomyDir',folder);ChipmunkSpikeGLTest.probeList='(0,4,NP2010)';
s=spikeglx_client('loadanatomy');
assert(~s.running && ~s.anatomyApplied && s.anatomyProfile.nShanks==4);
assert(contains(s.anatomyStatus,'Plan loaded') && ChipmunkSpikeGLTest.starts==0);
s=spikeglx_client('prepare');assert(s.anatomyApplied && numel(ChipmunkSpikeGLTest.anatomy)==4);
assert(strcmp(ChipmunkSpikeGLTest.metadata.chipmunk_anatomy_kind,'surgery plan'));
s=spikeglx_client('loadanatomy');assert(s.anatomyApplied && contains(s.actionLog{end},'Stop acquisition'));
spikeglx_client('set','anatomyDir','another-folder');s=spikeglx_client('get');
assert(strcmp(s.anatomyDir,folder) && contains(s.lastError,'Stop acquisition'));
s=spikeglx_client('prepare');assert(s.anatomyApplied && numel(ChipmunkSpikeGLTest.anatomy)==4);
spikeglx_client('shutdown');clear folderCleanup

% Lost acknowledgements and disconnected cleanup must preserve ownership safely.
resetServer();
folder=tempname;mkdir(folder);folderCleanup=onCleanup(@() rmdir(folder,'s'));
spikeglx_client('init','ephys','FakeSubject','20261103_120000');
spikeglx_client('set','host','localhost');spikeglx_client('set','dataDir',folder);
ChipmunkSpikeGLTest.loseStartAck=true;ChipmunkSpikeGLTest.startSaves=true;
s=spikeglx_client('prepare');
assert(s.running && s.ownedRun && ~s.startPending && ~s.recording && isempty(s.lastError),'%s',s.lastError);
assert(ChipmunkSpikeGLTest.starts==1,'Start was sent twice after losing its acknowledgement');
s=spikeglx_client('begin');assert(s.recording);
BpodSystem=struct('ProtocolSettings',struct('spikeGLXHost','localhost'),'Data',struct(),'PluginObjects',struct());
assertChipmunkRecording();
ChipmunkSpikeGLTest.saving=false;ChipmunkSpikeGLTest.targetSaving=false;
try,assertChipmunkRecording();error('Test:Accepted','Stopped recording was accepted');
catch e,assert(strcmp(e.identifier,'chipmunk_solo:RecordingLost'));end
assert(isfield(BpodSystem.Data,'EphysRecordingFailure'));
ChipmunkSpikeGLTest.saving=true;ChipmunkSpikeGLTest.targetSaving=true;
ChipmunkSpikeGLTest.pollFailure=true;spikeglx_client('refresh');
s=spikeglx_client('shutdown');assert(ChipmunkSpikeGLTest.running && contains(s.lastError,'Could not confirm'));
ChipmunkSpikeGLTest.pollFailure=false;
s=spikeglx_client('shutdown');assert(~ChipmunkSpikeGLTest.running && isempty(s.lastError));
spikeglx_client('set','host','another-host');s=spikeglx_client('get');assert(isempty(s.sessionDir));
resetServer();spikeglx_client('init','ephys','FakeSubject','20261103_120001');
spikeglx_client('set','host','localhost');spikeglx_client('set','dataDir',folder);
ChipmunkSpikeGLTest.loseStartAck=true;ChipmunkSpikeGLTest.afterStartDirectory='other-session';
s=spikeglx_client('prepare');assert(~s.ownedRun && ~isempty(s.lastError));
spikeglx_client('shutdown');assert(ChipmunkSpikeGLTest.running && ChipmunkSpikeGLTest.stops==0);
clear folderCleanup

resetServer();s=spikeglx_client('prepare');spikeglx_client('begin');
ChipmunkSpikeGLTest.pollFailure=true;spikeglx_client('refresh');
spikeglx_client('set','host','other-host');s=spikeglx_client('get');assert(strcmp(s.host,'unit-test'));
oldRoot=s.dataDir;spikeglx_client('set','dataDir','another-root');s=spikeglx_client('get');assert(strcmp(s.dataDir,oldRoot));
ChipmunkSpikeGLTest.pollFailure=false;ChipmunkSpikeGLTest.runName='AnotherSession';
s=spikeglx_client('shutdown');assert(ChipmunkSpikeGLTest.running && ChipmunkSpikeGLTest.stops==0);
assert(contains(s.lastError,'does not own'));

resetServer();spikeglx_client('prepare');
BpodSystem=struct('ProtocolSettings',struct('spikeGLXHost','unit-test','labcamsAddress','camera:9999'), ...
 'Data',struct(),'PluginObjects',struct());
[ok,message]=beginChipmunkRecording();assert(~ok && contains(message,'labcams'));
assert(~ChipmunkSpikeGLTest.saving,'Camera failure left ephys recording enabled');
BpodSystem.PluginObjects.labcams=TestCamera();
for reply={'','ERROR cannot record'}
 BpodSystem.PluginObjects.labcams.reply=reply{1};
 [ok,message]=beginChipmunkRecording();assert(~ok && contains(message,'acknowledgement'));
 assert(~ChipmunkSpikeGLTest.saving);
end
BpodSystem.PluginObjects.labcams.fail=true;
[ok,message]=beginChipmunkRecording();assert(~ok && contains(message,'connection failed'));
assert(~ChipmunkSpikeGLTest.saving);
BpodSystem.PluginObjects.labcams.fail=false;BpodSystem.PluginObjects.labcams.reply='ok';
BpodSystem.PluginObjects.labcams.failCommand='softtrigger=1';
[ok,message]=beginChipmunkRecording();assert(~ok && ~ChipmunkSpikeGLTest.saving);
assert(isequal(BpodSystem.PluginObjects.labcams.commands(end-1:end),{'softtrigger=0','manualsave=0'}));
BpodSystem.PluginObjects.labcams.failCommand='';
[ok,message]=beginChipmunkRecording();assert(ok && isempty(message));
assert(isequal(BpodSystem.PluginObjects.labcams.commands(end-2:end),{'softtrigger=0','manualsave=1','softtrigger=1'}));
spikeglx_client('shutdown');

resetServer();
settings=load(fullfile(root,'Experiments','VisualTask.mat'));
BpodSystem=struct('ProtocolSettings',settings.ProtocolSettings,'GUIHandles',struct(), ...
 'Data',struct('OutcomeRecord',[],'ValidTrials',[],'CorrectResponse',[], ...
 'EarlyWithdrawal',[],'DidNotChoose',[],'LeftSideRewardAmount',0,'RightSideRewardAmount',0));
BpodSystem.ProtocolSettings.spikeGLXHost='unit-test';
BpodSystem.ProtocolSettings.labcamsAddress='';
BpodSystem.ProtocolSettings.demonID='FakeSubject';BpodSystem.ProtocolSettings.demonWeight=25;
BpodSystem.ProtocolSettings.baseWait=.5;
ensurePassiveReplaySettings();ensureStimulusManipulationSettings();
DemonstratorFigure('init');fig=BpodSystem.GUIHandles.Figures.DemonFigure;
figCleanup=onCleanup(@() deleteIfValid(fig));
button=BpodSystem.GUIHandles.DemonStartButton;assert(strcmp(get(button,'String'),'Start session'));
assert(strcmp(get(button,'Enable'),'off'));
SpikeGLXControl('init');controlCleanup=onCleanup(@() SpikeGLXControl('shutdown'));
ha=BpodSystem.GUIHandles.SpikeGLX;
assert(contains(get(ha.title,'String'),'unit-test:4142'));
assert(~contains(get(ha.title,'String'),'Jupiter'));
assert(any(contains(string(get(ha.status,'String')),'SpikeGLX network: connected')));
assert(~any(contains(string(get(ha.status,'String')),'test server')));
assert(strcmp(get(ancestor(ha.anatomyDir,'uitab'),'Title'),'Anatomy'));
tabs=get(get(ancestor(ha.anatomyDir,'uitab'),'Parent'),'Children');
assert(isequal(get(tabs,'Title'),{'Devices';'Probe';'Analog';'Digital';'Anatomy'}));
labels=findall(BpodSystem.GUIHandles.Figures.SpikeGLX,'Type','uicontrol','Style','text');
for k=1:numel(labels),assert(~any(contains(string(get(labels(k),'String')),'Check probe docks')));end
set(ha.deviceTable,'Data',spikeglxDeviceRows(''));
invoke(ha.start);s=spikeglx_client('get');
assert(~s.running && contains(s.lastError,'at least one'));
devices='(20,1,2)(20,2,1)(20,obx)';ChipmunkSpikeGLTest.attached=devices;
set(ha.deviceTable,'Data',spikeglxDeviceRows(devices));
invoke(ha.start);assert(ChipmunkSpikeGLTest.running && ~ChipmunkSpikeGLTest.saving);
assert(strcmp(ChipmunkSpikeGLTest.devices,devices));
assert(strcmp(get(ha.deviceTable,'Enable'),'off'));
log=get(ha.actionLog,'String');assert(any(contains(log,'Prepared: acquisition ON; recording OFF')));
assert(strcmp(get(button,'Enable'),'on'));
invoke(button);assert(ChipmunkSpikeGLTest.saving && strcmp(get(button,'String'),'Update settings'));
SpikeGLXControl('shutdown');spikeglx_client('shutdown');
clear controlCleanup figCleanup
fprintf('PASS: Prepare/Start, delayed confirmation, detection/start failures, run ownership and cleanup\n');
end
function resetServer()
global ChipmunkSpikeGLTest
clear spikeglx_client
ChipmunkSpikeGLTest=struct('running',false,'saving',false,'targetSaving',false, ...
 'pending',0,'runName','','existingNames',{{}},'dataDir','test-data','validated',true,'startSaves',false, ...
 'detects',0,'connectFailure',false,'detectFailure',false,'startFailure',false,'starts',0,'stops',0,'enables',0,'devices','','attached','(20,1,1)(20,obx)','probeList','()','anatomy',{{}},'metadata',struct());
spikeglx_client('init','FakeSubject_workflow');spikeglx_client('set','host','unit-test');
spikeglx_client('set','devices','(20,1,1)(20,obx)');spikeglx_client('set','anatomyDir','');
end
function restore(oldPath,oldBpod,oldServer,prefs,hadPrefs,original)
global BpodSystem ChipmunkSpikeGLTest
clear spikeglx_client SpikeGL
path(oldPath);BpodSystem=oldBpod;ChipmunkSpikeGLTest=oldServer;
if hadPrefs,fid=fopen(prefs,'w');fwrite(fid,original,'uint8');fclose(fid);
elseif isfile(prefs),delete(prefs);end
end

function invoke(button)
cb=get(button,'Callback');
if iscell(cb),feval(cb{1},button,[],cb{2:end});else,feval(cb,button,[]);end
end
function deleteIfValid(fig)
if isgraphics(fig),delete(fig);end
end
