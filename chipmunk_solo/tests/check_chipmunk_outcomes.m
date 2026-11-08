function check_chipmunk_outcomes(outputFolder, modality, correctSide, isPoisson, syncMode)
if nargin < 4, isPoisson = 1; end
if nargin < 5, syncMode = 1; end
% Five full trials: correct, wrong, early pre-stimulus, early stimulus, no choice.
% Run in an idle Bpod emulator; no cameras, hardware rewards or uploads.
global BpodSystem ChipmunkSessionTest
assert(BpodSystem.EmulatorMode == 1 && BpodSystem.Status.BeingUsed == 0);
root = fileparts(fileparts(mfilename('fullpath')));
oldPaths = BpodSystem.Path;
oldFolder = pwd;
oldLab = getenv('LABDATA_PATH');
cleanup = onCleanup(@() restore(oldPaths,oldFolder,oldLab));
addpath(root,fullfile(root,'tests'),genpath(fullfile(root,'Functions')));
mkdir(outputFolder);
cd(outputFolder); % Match rig launches where the protocol is not the current folder.
% Synthetic calibration is for emulator waveforms only; no production files are edited.
local = fullfile(outputFolder,'Bpod Local');
mkdir(fullfile(local,'Calibration Files'));
TargetSPLs = [40 50 60];
NoiseAmplitudes = [.001 .01 .1];
save(fullfile(local,'Calibration Files','WhiteNoiseCalibration.mat'),'TargetSPLs','NoiseAmplitudes');
BpodSystem.Path.LocalDir = local;
BpodSystem.Path.ProtocolFolder = fileparts(root);
BpodSystem.Path.DataFolder = fullfile(outputFolder,'Data');
isolateLabdataPrefs(BpodSystem.Path.DataFolder);

experiment = 'MultipleModalitiesTask';
settings = load(fullfile(root,'Experiments',[experiment '.mat']));
s = settings.ProtocolSettings;
s.demonID = 'FakeSubject';
s.labcamsAddress = '';
s.spikeGLXHost = '';
s.propLeft = 1-correctSide;
s.propOnlyVisual = double(modality==1);
s.propOnlyAuditory = double(modality==2);
s.isPoissonStim = isPoisson;
s.syncMultiSensory = syncMode;
s.antiBiasStrength = 0;
s.minWaitTime = .2;
s.timeToChoose = .2;
s.earlyPunishTimeout = .03;
s.wrongPunishTimeout = .03;
s.minWaitTimeStep = 0;
s.interTrialDurMin = .01;
s.interTrialDurMax = .02;
s.preStimDelayMin = .15;
s.preStimDelayMax = .15;
s.stimLoudness = 40;
s.goCueLoudness = 40;
s.wrongPunishLoudness = 40;
s.earlyPunishLoudness = 40;
s.extraStimDur = .05;
s.passiveReplayEnable = 0; % Isolate active outcome and reward accounting.
BpodSystem.ProtocolSettings = s;
settingsFolder = fullfile(outputFolder,'FakeSubject','chipmunk_solo','Session Settings');
mkdir(settingsFolder);
BpodSystem.Path.Settings = fullfile(settingsFolder,[experiment '.mat']);
BpodSystem.Data = struct();
BpodSystem.Status.BeingUsed = 1;
BpodSystem.Status.CurrentProtocolName = 'chipmunk_solo';
BpodSystem.Status.CurrentStateName = '';
BpodSystem.ProtocolStartTime = now;
ChipmunkSessionTest = struct('centerHeld',false, ...
    'correctSide',correctSide,'stopped',false,'snapshot',struct(),'started',tic,'error','','lastState','');
assert(isempty(timerfindall('Tag','ChipmunkSessionDriver')), 'Previous session driver leaked.');
driver = timer('Tag','ChipmunkSessionDriver','ExecutionMode','fixedSpacing','Period',.03,'TimerFcn',@driveSession);
ChipmunkSessionTest.driver = driver;
driverCleanup = onCleanup(@() deleteIfValid(driver));
start(driver);
chipmunk_solo;
stop(driver);
callback = get(driver,'TimerFcn');
delete(driver);
callback(driver,[]); % A late callback from a deleted session must be harmless.
clear driverCleanup
assert(isempty(timerfindall('Tag','ChipmunkSessionDriver')), 'Session driver was not deleted.');
assert(isempty(ChipmunkSessionTest.error),ChipmunkSessionTest.error);
assert(ChipmunkSessionTest.stopped,'Driver did not reach active Stop.');
saved = load(BpodSystem.Path.CurrentDataFile{1});
data = saved.SessionData;
assert(numel(data.Modality)==5 && all(data.Modality==modality));
assert(isequal(data.OutcomeRecord,[1 0 -1 -1 2]));
assert(isequal(logical(data.ValidTrials),logical([1 1 0 0 0])));
assert(isequaln(data.ResponseSide,[correctSide 1-correctSide NaN NaN NaN]));
assert(isequal(logical(data.Rewarded),logical([1 0 0 0 0])));
assert(all(data.CorrectSide==correctSide));
assert(data.LeftSideRewardAmount == (correctSide==0)*data.TrialSettings(1).leftRewardVolume);
assert(data.RightSideRewardAmount == (correctSide==1)*data.TrialSettings(1).rightRewardVolume);
assert(all(isnan(data.RawEvents.Trial{3}.States.PlayStimulus)));
assert(any(isfinite(data.RawEvents.Trial{4}.States.PlayStimulus)));
assert(any(isfinite(data.RawEvents.Trial{2}.States.DemonWrongChoicePunishment)));
assert(any(isfinite(data.RawEvents.Trial{5}.States.DemonDidNotChoose)));
fields = {'Modality','TrialSettings','RawEvents','InterStimulusIntervalList'};
for k = 1:numel(fields)
    assert(isequaln(data.(fields{k}),ChipmunkSessionTest.snapshot.(fields{k})));
end
assert(~isfield(data,'PassiveReplay'));
duration = 1 + .02*double(~isPoisson && modality==3 && syncMode~=1);
for line = [BpodSystem.GUIHandles.StimulusPlotVisualLine BpodSystem.GUIHandles.StimulusPlotAuditoryLine]
    assert(numel(line.XData)==numel(line.YData));
    assert(abs(line.XData(end)-duration)<1e-9);
end
assert(BpodSystem.Status.BeingUsed == 0);
assert(~isfield(BpodSystem.PluginObjects,'SoundServer'));
fprintf('PASS: outcome branches modality=%d correctSide=%d saved %s\n',modality,correctSide,BpodSystem.Path.CurrentDataFile{1});
close(BpodSystem.GUIHandles.Figures.DemonFigure);
addpath(root);
end

function driveSession(driver,~)
global BpodSystem ChipmunkSessionTest
% Deleted timers can still have a callback queued during the next GUI startup.
if ~isvalid(driver) || ~isstruct(ChipmunkSessionTest) || ...
        ~isfield(ChipmunkSessionTest,'driver') || ~isequal(driver,ChipmunkSessionTest.driver)
    return
end
try
    if toc(ChipmunkSessionTest.started) > 90
        ChipmunkSessionTest.error = 'Full-session emulator test timed out.';
        stop(driver);
        RunProtocol('Stop');
        if isfield(BpodSystem.GUIHandles,'Figures') && ...
                isfield(BpodSystem.GUIHandles.Figures,'DemonFigure') && ...
                isgraphics(BpodSystem.GUIHandles.Figures.DemonFigure)
            uiresume(BpodSystem.GUIHandles.Figures.DemonFigure);
        end
        return
    end
    init = findall(findall(0,'Tag','ChipmunkInit'),'Style','pushbutton','String','Initialize');
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
    if ~strcmp(state,ChipmunkSessionTest.lastState)
        fprintf('Emulator driver state: %s\n',state);
        ChipmunkSessionTest.lastState = state;
    end
    nDone = 0;
    if isfield(BpodSystem.Data,'TrialSettings'), nDone = numel(BpodSystem.Data.TrialSettings); end
    trial = nDone+1;
    leftHeld = BpodSystem.HardwareState.InputState(ports(1)) ~= 0;
    rightHeld = BpodSystem.HardwareState.InputState(ports(3)) ~= 0;
    if strcmp(state,'DemonWaitForCenterFixation')
        if nDone >= 5
            ChipmunkSessionTest.snapshot = BpodSystem.Data;
            ChipmunkSessionTest.stopped = true;
            RunProtocol('Stop');
        elseif leftHeld
            ManualOverride('IP',1);
        elseif rightHeld
            ManualOverride('IP',3);
        elseif ~ChipmunkSessionTest.centerHeld
            ManualOverride('IP',2);
        end
    elseif strcmp(state,'PreStimPeriod') && trial==3 && ChipmunkSessionTest.centerHeld
        ManualOverride('IP',2);
    elseif strcmp(state,'DemonCenterFixationPeriod') && trial==4 && ChipmunkSessionTest.centerHeld
        ManualOverride('IP',2);
    elseif strcmp(state,'DemonWaitForWithdrawalFromCenter') && ChipmunkSessionTest.centerHeld
        ManualOverride('IP',2);
    elseif strcmp(state,'DemonWaitForResponse') && trial<=2 && ~leftHeld && ~rightHeld
        side = ChipmunkSessionTest.correctSide;
        if trial==2, side = 1-side; end
        ManualOverride('IP',1+2*side);
    end

catch ME
    ChipmunkSessionTest.error = ME.message;
    warning('ReplayEmulator:Driver', '%s', getReport(ME,'extended','hyperlinks','off'));
    init = findall(findall(0,'Tag','ChipmunkInit'),'Style','pushbutton','String','Initialize');
    if ~isempty(init)
        close(ancestor(init(1),'figure'));
    end
    stop(driver);
    RunProtocol('Stop');
    if isfield(BpodSystem.GUIHandles,'Figures') && ...
                isfield(BpodSystem.GUIHandles.Figures,'DemonFigure') && ...
                isgraphics(BpodSystem.GUIHandles.Figures.DemonFigure)
        uiresume(BpodSystem.GUIHandles.Figures.DemonFigure);
    end
end
end

function restore(paths,folder,oldLab)
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

function deleteIfValid(driver)
if isvalid(driver)
    delete(driver);
end
end
