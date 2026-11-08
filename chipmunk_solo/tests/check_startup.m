function check_startup()
% Subject validation and the selected camera JSON must survive startup unchanged.
root = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
global BpodSystem
oldBpod = BpodSystem;
oldLab = getenv('LABDATA_PATH');
cleanup = onCleanup(@() restore(oldPath,oldBpod,oldLab));
addpath(fullfile(root,'tests'), genpath(fullfile(root,'Functions')));
assert(strcmp(validateChipmunkSubject(' FakeSubject '),'FakeSubject'));
for name = {'Virtual','Dummy','virtual','../mouse','', 'mouse/name'}
    try
        validateChipmunkSubject(name{1});
        error('Test:ExpectedError','Invalid subject accepted.');
    catch ME
        assert(startsWith(ME.identifier,'chipmunk_solo:'));
    end
end
folder = tempname;
mkdir(folder);
folderCleanup = onCleanup(@() rmdir(folder,'s'));
config = fullfile(folder, 'camera '' $(echo wrong).json');
fid = fopen(config,'w');
fprintf(fid,'{"cams":[{"name":"test"}]}');
fclose(fid);
command = labcamsLaunchCommand(config);
argument = extractAfter(command,'labcams -w ');
[status, echoed] = system(['printf ''%s'' ' char(argument)]);
assert(status==0 && strcmp(echoed,config), 'Camera config must be one literal shell argument.');
assert(endsWith(labcamsLaunchCommand(''),'labcams -w'));
% An already-completed initialization must return immediately, not wait for another change.
fig = figure('Visible','off','UserData',true);
tick = tic;
waitfor(fig,'UserData',true);
assert(toc(tick)<.5);
close(fig);
try
    labcamsLaunchCommand(fullfile(folder,'absent.json'));
    error('Test:ExpectedError','Missing camera config accepted.');
catch ME
    assert(strcmp(ME.identifier,'chipmunk_solo:CameraConfig'));
end
% Use the real initialization callback and waitfor, without starting devices.
s = load(fullfile(root,'Experiments','VisualTask.mat'));
BpodSystem = struct('ProtocolSettings',s.ProtocolSettings,'Path',struct());
BpodSystem.ProtocolSettings.labcamsConfig = config;
BpodSystem.Path.DataFolder = fullfile(folder,'Data');
isolateLabdataPrefs(BpodSystem.Path.DataFolder);
assert(strcmp(chipmunkDataRoot(), BpodSystem.Path.DataFolder));
BpodSystem.Path.Settings = fullfile(folder,'FakeSubject','chipmunk_solo','Session Settings','VisualTask.mat');
driver = timer('ExecutionMode','fixedSpacing','Period',.001,'TimerFcn',@initialize);
driverCleanup = onCleanup(@() delete(driver));
start(driver);
settings = initChipmunk;
stop(driver);
assert(strcmp(settings.demonID,'FakeSubject'));
assert(strcmp(settings.labcamsConfig,config));
assert(iscell(BpodSystem.Path.CurrentDataFile) && contains(BpodSystem.Path.CurrentDataFile{1},'FakeSubject'));
assert(startsWith(BpodSystem.Path.CurrentDataFile{1}, BpodSystem.Path.DataFolder));
assert(~isempty(settings.rigNo) && ~isempty(settings.researcher), 'Initialization must publish metadata atomically.');
set(driver,'TimerFcn',@cancelInitialization);
start(driver);
try
    initChipmunk;
    error('Test:ExpectedError','Closing initialization should cancel startup.');
catch ME
    assert(strcmp(ME.identifier,'chipmunk_solo:InitializationCancelled'),getReport(ME,'extended','hyperlinks','off'));
end
stop(driver);
assert(BpodSystem.Status.BeingUsed == 0);
disp('PASS: reserved subject rejection, literal camera config path and atomic GUI initialization');
end
function initialize(~,~)
fig = findall(0,'Tag','ChipmunkInit');
if isempty(fig), return; end
button = findall(fig,'String','Initialize');
if isempty(button), return; end
cb = get(button,'Callback');
h = cb{2};
set(h.demonID,'String','FakeSubject');
set(h.rigNo,'String','test');
set(h.researcher,'String','test');
feval(cb{1},button,[],cb{2:end});
end
function restore(oldPath,oldBpod,oldLab)
global BpodSystem
path(oldPath);
BpodSystem = oldBpod;
if isempty(oldLab)
    setenv('LABDATA_PATH','');
else
    setenv('LABDATA_PATH',oldLab);
end
end

function cancelInitialization(~,~)
fig = findall(0,'Tag','ChipmunkInit');
if ~isempty(fig) && strcmp(get(fig,'Visible'),'on')
    close(fig);
end
end
