function check_chipmunk_manipulation_session(outputFolder, modality, syncMode)
if nargin < 2, modality = 1; end
if nargin < 3, syncMode = 1; end
% FakeSubject emulator: Standard, Dim, Long, then Equalized luminance.
global BpodSystem ChipmunkSessionTest
assert(BpodSystem.EmulatorMode == 1 && BpodSystem.Status.BeingUsed == 0);
root = fileparts(fileparts(mfilename('fullpath')));
oldPaths = BpodSystem.Path;
oldFolder = pwd;
oldLab = getenv('LABDATA_PATH');
cleanup = onCleanup(@() restore(oldPaths, oldFolder, oldLab));
addpath(root, fullfile(root,'tests'), genpath(fullfile(root,'Functions')));
mkdir(outputFolder);
cd(outputFolder);
local = fullfile(outputFolder,'Bpod Local');
mkdir(fullfile(local,'Calibration Files'));
TargetSPLs = [40 50 60];
NoiseAmplitudes = [.001 .01 .1];
save(fullfile(local,'Calibration Files','WhiteNoiseCalibration.mat'),'TargetSPLs','NoiseAmplitudes');
BpodSystem.Path.LocalDir = local;
BpodSystem.Path.ProtocolFolder = fileparts(root);
BpodSystem.Path.DataFolder = fullfile(outputFolder,'Data');
isolateLabdataPrefs(BpodSystem.Path.DataFolder);

settings = load(fullfile(root,'Experiments','MultipleModalitiesTask.mat'));
s = settings.ProtocolSettings;
s.demonID = 'FakeSubject';
s.labcamsAddress = '';
s.spikeGLXHost = '';
s.propLeft = 1;
s.antiBiasStrength = 0;
s.minWaitTime = .1;
s.minWaitTimeStep = 0;
s.interTrialDurMin = .01;
s.interTrialDurMax = .02;
s.preStimDelayMin = .01;
s.preStimDelayMax = .02;
s.stimLoudness = 40;
s.goCueLoudness = 40;
s.wrongPunishLoudness = 40;
s.earlyPunishLoudness = 40;
s.extraStimDur = .05;
s.passiveReplayEnable = 1;
s.passiveReplayFraction = 1;
s.passiveReplayNTrials = 8;
s.passiveReplayOrder = 'sequential';
s.propOnlyVisual = double(modality == 1);
s.propOnlyAuditory = double(modality == 2);
s.syncMultiSensory = syncMode;
s.visEventRateList = [4 20];
s.audEventRateList = [4 20];
s.multEventRateList = [4 20];
s.stimBrightness = 100;
BpodSystem.ProtocolSettings = s;
ensureStimulusManipulationSettings();
settingsFolder = fullfile(outputFolder,'FakeSubject','chipmunk_solo','Session Settings');
mkdir(settingsFolder);
BpodSystem.Path.Settings = fullfile(settingsFolder,'MultipleModalitiesTask.mat');
ProtocolSettings = BpodSystem.ProtocolSettings;
save(BpodSystem.Path.Settings, 'ProtocolSettings');
BpodSystem.Data = struct();
BpodSystem.Status.BeingUsed = 1;
BpodSystem.Status.CurrentProtocolName = 'chipmunk_solo';
BpodSystem.Status.CurrentStateName = '';
BpodSystem.ProtocolStartTime = now;
ChipmunkSessionTest = struct('centerHeld',false,'sideHeld',false,'stopped',false, ...
    'started',tic,'error','','lastState','','phase','standard','applied',false, ...
    'beforeReplay',struct(), 'screenshots',fullfile(outputFolder,'gui'));
mkdir(ChipmunkSessionTest.screenshots);
driver = timer('ExecutionMode','fixedSpacing','Period',.03,'TimerFcn',@driveSession);
ChipmunkSessionTest.driver = driver;
driverCleanup = onCleanup(@() deleteIfValid(driver));
start(driver);
chipmunk_solo;
stop(driver);
delete(driver);
clear driverCleanup
assert(isempty(ChipmunkSessionTest.error), ChipmunkSessionTest.error);
assert(ChipmunkSessionTest.stopped, 'Driver did not reach Stop.');
saved = load(BpodSystem.Path.CurrentDataFile{1});
data = saved.SessionData;
assert(numel(data.Modality) == 8 && all(data.Modality == modality));
assert(isfield(data,'StimulusBrightness') && isfield(data,'MinInterval'));
assert(all(data.StimulusBrightness(1:2) == 100));
assert(all(abs(data.StimulusDuration(1:2) - 0.015) < 1e-9));
assert(all(data.StimulusBrightness(3:4) == 30));
assert(all(data.TrialSettings(3).stimBrightness == 30));
assert(all(data.TrialSettings(1).stimBrightness == 100));
assert(all(abs(data.StimulusDuration(5:6) - 0.075) < 1e-9));
assert(all(abs(data.MinInterval(5:6) - 0.125) < 1e-9));
assert(all(data.StimulusBrightness(7:8) == 20));
assert(all(abs(data.StimulusDuration(7:8) - 0.015) < 1e-9));
assert(contains(char(data.Notes{3}), 'manipPreset'));
assert(contains(char(data.Notes{5}), 'manipPreset'));
assert(contains(char(data.Notes{7}), 'manipPreset'));
notesFile = fullfile(fileparts(BpodSystem.Path.CurrentDataFile{1}), 'notes.txt');
assert(exist(notesFile,'file') == 2);
text = fileread(notesFile);
lines = regexp(strtrim(text), '\r?\n', 'split');
assert(numel(lines) == 3, 'Expected exactly three automatic settings notes.');
for k = 1:3
    trial = [3 5 7];
    assert(strcmp(lines{k}, sprintf('Trial %d: %s', trial(k), data.SettingsNotes{trial(k)})));
    assert(strcmp(data.Notes{trial(k)}, data.SettingsNotes{trial(k)}));
end
replay = data.PassiveReplay;
assert(strcmp(replay.status,'completed') && replay.nCompleted == 8);
assert(isequal(replay.sourceTrialNumbers,1:8));
fields = {'TrialSettings','Modality','StimulusBrightness','StimulusDuration', ...
    'MinInterval','InterStimulusIntervalList','ExtraStimDuration','RawEvents'};
for k = 1:numel(fields)
    name = fields{k};
    assert(isequaln(data.(name), ChipmunkSessionTest.beforeReplay.(name)), ...
        ['Replay changed active data: ' name]);
end
addpath(root, genpath(fullfile(root,'Functions')));
% Deliberately conflicting current settings must not affect saved-source reconstruction.
oldSettings = BpodSystem.ProtocolSettings;
BpodSystem.ProtocolSettings.stimBrightness = 999;
BpodSystem.ProtocolSettings.manipNormalPulseMs = 99;
for trial = 1:8
    rngState = rng;
    [signal, duration] = rebuildTrialStimSignals(trial, 192000);
    rng(rngState);
    channels = cell(1,2);
    for channel = 1:2
        if modality ~= 3 && modality ~= channel, continue; end
        isi = data.InterStimulusIntervalList{trial,channel};
        if channel == 1
            channels{channel} = createVisualStimSignal(isi,192000, ...
                data.StimulusBrightness(trial),data.StimulusDuration(trial));
        else
            settings = data.TrialSettings(trial);
            channels{channel} = createAuditoryStimSignal(isi,192000, ...
                data.StimulusDuration(trial),'whiteNoise + envelope', ...
                settings.stimLoudness,10,settings.soundCalibrationModelParams);
        end
    end
    expected = zeros(2,max(cellfun(@numel,channels)));
    for channel = 1:2
        expected(channel,1:numel(channels{channel})) = channels{channel};
    end
    expected = extendStimulusTrain(expected,data.ExtraStimDuration(trial),192000);
    assert(isequal(signal,expected), 'Reconstruction differs from saved effective parameters.');
    if modality == 3 && syncMode == 1
        assert(isequal(data.InterStimulusIntervalList{trial,1},data.InterStimulusIntervalList{trial,2}));
    end
    seen = seenStimulusDuration(data.RawEvents.Trial{trial}.States);
    expectedDuration = min(duration, max(1, round(seen*192000))/192000);
    assert(abs(expectedDuration-replay.stimDurations(trial)) < 1e-9, 'Replay did not stop where the task stopped the stimulus.');
end
BpodSystem.ProtocolSettings = oldSettings;
fprintf('PASS: eight replay sources preserve active data and saved effective parameters\n');
fprintf('Saved notes.txt:\n%s', text);
fprintf('PASS: manipulation modality=%d sync=%d session saved %s\n', modality,syncMode,BpodSystem.Path.CurrentDataFile{1});
close(BpodSystem.GUIHandles.Figures.DemonFigure);
end

function driveSession(driver,~)
global BpodSystem ChipmunkSessionTest
if ~isvalid(driver) || ~isstruct(ChipmunkSessionTest) || ...
        ~isfield(ChipmunkSessionTest,'driver') || ~isequal(driver,ChipmunkSessionTest.driver)
    return
end
try
    if toc(ChipmunkSessionTest.started) > 180
        ChipmunkSessionTest.error = 'Manipulation emulator test timed out.';
        stop(driver);
        RunProtocol('Stop');
        return
    end
    init = findall(0,'Style','pushbutton','String','Initialize');
    if ~isempty(init)
        callback = get(init(1),'Callback');
        handles = callback{2};
        set(handles.demonID,'String','FakeSubject');
        set(handles.demonWeight,'String','25');
        set(handles.rigNo,'String','emulator');
        set(handles.researcher,'String','test');
        feval(callback{1},init(1),[],callback{2:end});
        return
    end
    if isfield(BpodSystem.GUIHandles,'DemonStartButton') && isgraphics(BpodSystem.GUIHandles.DemonStartButton)
        button = BpodSystem.GUIHandles.DemonStartButton;
        if strcmp(get(button,'String'),'Start') && ...
                strcmp(get(BpodSystem.GUIHandles.Figures.DemonFigure,'WaitStatus'),'waiting')
            captureGui('standard');
            callback = get(button,'Callback');
            if iscell(callback)
                feval(callback{1},button,[],callback{2:end});
            else
                feval(callback,button,[]);
            end
            return
        end
    end
    if ChipmunkSessionTest.stopped || ~BpodSystem.Status.BeingUsed
        return
    end
    state = BpodSystem.Status.CurrentStateName;
    ports = find(BpodSystem.HW.Inputs == 'P');
    ChipmunkSessionTest.centerHeld = BpodSystem.HardwareState.InputState(ports(2)) ~= 0;
    ChipmunkSessionTest.sideHeld = BpodSystem.HardwareState.InputState(ports(1)) ~= 0;
    nDone = 0;
    if isfield(BpodSystem.Data,'TrialSettings')
        nDone = numel(BpodSystem.Data.TrialSettings);
    end
    if strcmp(state,'DemonWaitForCenterFixation')
        if nDone >= 8
            ChipmunkSessionTest.beforeReplay = BpodSystem.Data;
            ChipmunkSessionTest.stopped = true;
            RunProtocol('Stop');
            return
        elseif nDone == 1 && ~ChipmunkSessionTest.applied
            selectPreset(2);
            set(BpodSystem.GUIHandles.ParamEdit.manipFractionPercent,'String','100');
            callback = get(BpodSystem.GUIHandles.DemonStartButton,'Callback');
            feval(callback, BpodSystem.GUIHandles.DemonStartButton, []);
            ChipmunkSessionTest.applied = true;
            ChipmunkSessionTest.phase = 'dim';
            captureGui('dim');
        elseif nDone == 3 && strcmp(ChipmunkSessionTest.phase,'dim')
            selectPreset(3);
            set(BpodSystem.GUIHandles.ParamEdit.manipEligibleRates,'String','4');
            set(BpodSystem.GUIHandles.ParamEdit.visEventRateList,'String','4');
            set(BpodSystem.GUIHandles.ParamEdit.audEventRateList,'String','4');
            set(BpodSystem.GUIHandles.ParamEdit.multEventRateList,'String','4');
            callback = get(BpodSystem.GUIHandles.DemonStartButton,'Callback');
            feval(callback, BpodSystem.GUIHandles.DemonStartButton, []);
            ChipmunkSessionTest.phase = 'long';
            captureGui('long');
        elseif nDone == 5 && strcmp(ChipmunkSessionTest.phase,'long')
            selectPreset(4);
            set(BpodSystem.GUIHandles.ParamEdit.visEventRateList,'String','4 20');
            set(BpodSystem.GUIHandles.ParamEdit.audEventRateList,'String','4 20');
            set(BpodSystem.GUIHandles.ParamEdit.multEventRateList,'String','4 20');
            set(BpodSystem.GUIHandles.ParamEdit.propLeft,'String','0');
            callback = get(BpodSystem.GUIHandles.DemonStartButton,'Callback');
            feval(callback, BpodSystem.GUIHandles.DemonStartButton, []);
            ChipmunkSessionTest.phase = 'equalized';
            captureGui('equalized');
        elseif ChipmunkSessionTest.sideHeld
            ManualOverride('IP',1);
            ChipmunkSessionTest.sideHeld = false;
        elseif ~ChipmunkSessionTest.centerHeld
            ManualOverride('IP',2);
            ChipmunkSessionTest.centerHeld = true;
        end
    elseif strcmp(state,'DemonWaitForWithdrawalFromCenter') && ChipmunkSessionTest.centerHeld
        ManualOverride('IP',2);
        ChipmunkSessionTest.centerHeld = false;
    elseif strcmp(state,'DemonWaitForResponse') && ~ChipmunkSessionTest.sideHeld
        ManualOverride('IP',1);
        ChipmunkSessionTest.sideHeld = true;
    end
catch ME
    ChipmunkSessionTest.error = ME.message;
    warning('ManipEmulator:Driver', '%s', ME.message);
    stop(driver);
    RunProtocol('Stop');
end
end

function restore(paths, folder, oldLab)
global BpodSystem ChipmunkSessionTest
BpodSystem.Path = paths;
cd(folder);
ChipmunkSessionTest = [];
if isempty(oldLab)
    setenv('LABDATA_PATH','');
else
    setenv('LABDATA_PATH',oldLab);
end
end

function captureGui(name)
global BpodSystem ChipmunkSessionTest
BpodSystem.GUIHandles.DemonFigTabs.SelectedTab = BpodSystem.GUIHandles.DemonTabGroup.TaskControl;
drawnow;
frame = getframe(BpodSystem.GUIHandles.Figures.DemonFigure);
imwrite(frame.cdata, fullfile(ChipmunkSessionTest.screenshots, ['manipulation-' name '.png']));
end

function selectPreset(value)
global BpodSystem
control = BpodSystem.GUIHandles.ParamEdit.manipPreset;
set(control,'Value',value);
callback = get(control,'Callback');
feval(callback,control,[]);
end

function deleteIfValid(driver)
if isvalid(driver), delete(driver); end
end
