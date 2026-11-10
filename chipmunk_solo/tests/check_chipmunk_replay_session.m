function check_chipmunk_replay_session(outputFolder, experiments, cameraConfig, trialLimit, badReplayEnable, runnerName)
if nargin < 6
    runnerName = 'chipmunk_solo';
end
if nargin < 5
    badReplayEnable = '';
end
if nargin < 4
    trialLimit = [];
end
if nargin < 3
    cameraConfig = '';
end
if nargin < 2
    experiments = {'VisualTask', 'MultipleModalitiesTask', 'VisualTask'};
end
assert(isempty(badReplayEnable) || ~isempty(trialLimit), 'Invalid replay edit requires natural completion.');
% Full FakeSubject protocol integration. Run only in a fresh, idle Bpod emulator, or on an idle
% real Bpod with CHIPMUNK_REAL_BPOD_CHECK=1 (run_rig_checks.sh real).
global BpodSystem ChipmunkSessionTest
assert(BpodSystem.Status.BeingUsed == 0 && (BpodSystem.EmulatorMode == 1 || strcmp(getenv('CHIPMUNK_REAL_BPOD_CHECK'), '1')), ...
    'Run in an idle Bpod emulator, or set CHIPMUNK_REAL_BPOD_CHECK=1 for a real Bpod.');
root = fileparts(fileparts(mfilename('fullpath')));
oldPaths = BpodSystem.Path;
oldFolder = pwd;
oldLab = getenv('LABDATA_PATH');
cleanup = onCleanup(@() restore(oldPaths,oldFolder,oldLab));
addpath(root,fullfile(root,'tests'),genpath(fullfile(root,'Functions')));
if ~strcmp(runnerName,'chipmunk_solo')
    addpath(fullfile(root,'compat',runnerName));
end
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

for session = 1:numel(experiments)
    if ~strcmp(runnerName,'chipmunk_solo')
        addpath(fullfile(root,'compat',runnerName));
    end
    enabled = session > 1;
    experiment = experiments{session};
    settings = load(fullfile(root,'Experiments',[experiment '.mat']));
    s = settings.ProtocolSettings;
    s.demonID = 'FakeSubject';
    s.labcamsAddress = '';
    if ~isempty(cameraConfig)
        config = jsondecode(fileread(cameraConfig));
        s.labcamsConfig = cameraConfig;
        s.labcamsAddress = sprintf('127.0.0.1:%d',config.server_port);
    end
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
    if ~isempty(trialLimit) && trialLimit > 3
        s.minWaitTime = .001;
        s.preStimDelayMin = .001;
        s.preStimDelayMax = .001;
        s.interTrialDurMin = 0;
        s.interTrialDurMax = 0;
        s.extraStimDur = 0;
    end
    s.passiveReplayEnable = 0; % Enabled only by editing the controls at Stop.
    BpodSystem.ProtocolSettings = s;
    settingsFolder = fullfile(outputFolder,'FakeSubject',runnerName,'Session Settings');
    mkdir(settingsFolder);
    BpodSystem.Path.Settings = fullfile(settingsFolder,[experiment '.mat']);
    BpodSystem.Data = struct();
    BpodSystem.Status.BeingUsed = 1;
    BpodSystem.Status.CurrentProtocolName = runnerName;
    BpodSystem.Status.CurrentStateName = '';
    BpodSystem.ProtocolStartTime = now*100000;
    ChipmunkSessionTest = struct('enable',enabled,'centerHeld',false,'sideHeld',false, ...
        'trialLimit',trialLimit,'badReplayEnable',badReplayEnable,'natural',~isempty(trialLimit), ...
        'stopped',false,'snapshot',struct(),'started',tic,'error','','lastState','');
    assert(isempty(timerfindall('Tag','ChipmunkSessionDriver')), 'Previous session driver leaked.');
    period = .03;
    if ~isempty(trialLimit) && trialLimit > 3, period = .005; end
    driver = timer('Tag','ChipmunkSessionDriver','ExecutionMode','fixedSpacing','Period',period,'TimerFcn',@driveSession);
    ChipmunkSessionTest.driver = driver;
    driverCleanup = onCleanup(@() deleteIfValid(driver));
    start(driver);
    if isempty(trialLimit)
        feval(runnerName);
    else
        feval(runnerName,trialLimit);
    end
    stop(driver);
    callback = get(driver,'TimerFcn');
    delete(driver);
    callback(driver,[]); % A late callback from a deleted session must be harmless.
    clear driverCleanup
    assert(isempty(timerfindall('Tag','ChipmunkSessionDriver')), 'Session driver was not deleted.');
    assert(isempty(ChipmunkSessionTest.error),ChipmunkSessionTest.error);
    assert(ChipmunkSessionTest.stopped || ~isempty(trialLimit),'Driver did not reach active Stop.');
    saved = load(BpodSystem.Path.CurrentDataFile{1});
    data = saved.SessionData;
    expectedTrials = 3;
    if ~isempty(trialLimit), expectedTrials = trialLimit; end
    assert(numel(data.Modality) == expectedTrials);
    if strcmp(experiment, 'PassiveVisualStim')
        assert(all(data.ValidTrials == 0) && all(isnan(data.ResponseSide)));
        assert(~any(data.Rewarded));
        for trial = 1:3
            interval = data.RawEvents.Trial{trial}.States.PlayStimulus;
            assert(diff(interval) >= 1.04, 'Passive playback ended before the full train.');
        end
    else
        assert(all(data.ValidTrials == 1));
    end
    if isempty(trialLimit)
        fields = {'Modality','TrialSettings','RawEvents','InterStimulusIntervalList'};
        for k = 1:numel(fields)
            assert(isequaln(data.(fields{k}),ChipmunkSessionTest.snapshot.(fields{k})));
        end
    end
    if ~isempty(cameraConfig)
        assert(strcmp(data.TrialSettings(1).labcamsConfig,cameraConfig));
    end
    [taskFolder,taskName] = fileparts(BpodSystem.Path.CurrentDataFile{1});
    passiveFile = fullfile(fileparts(taskFolder),'chipmunk_passive',[taskName '.mat']);
    if ~isempty(badReplayEnable)
        assert(strcmp(data.PassiveReplay.status,'failed') && data.PassiveReplay.nCompleted == 0);
        assert(~isempty(data.PassiveReplay.errorMessage));
    elseif enabled
        assert(data.PassiveReplay.nCompleted == 3 && strcmp(data.PassiveReplay.status,'completed'));
        passive = load(passiveFile);
        assert(isequaln(passive.PassiveReplay,data.PassiveReplay),'Passive dataset copy differs from the task file.');
    else
        assert(~isfield(data,'PassiveReplay'));
    end
    if isempty(badReplayEnable) && ~enabled
        assert(~exist(passiveFile,'file'),'Disabled replay wrote a passive dataset.');
    end
    assert(BpodSystem.Status.BeingUsed == 0);
    assert(isequal(get(BpodSystem.GUIHandles.RunButton,'CData'),BpodSystem.GUIData.GoButton), ...
        'Bpod console still displays Pause after session/replay completion.');
    assert(BpodSystem.Status.InStateMatrix == 0 && BpodSystem.Status.Live == 0);
    assert(strcmp(get(BpodSystem.GUIHandles.DemonStartButton,'String'),'Finished') && ...
        strcmp(get(BpodSystem.GUIHandles.DemonStartButton,'Enable'),'off'));
    assert(~isfield(BpodSystem.PluginObjects,'SoundServer'));
    print(BpodSystem.GUIHandles.MainFig,fullfile(outputFolder,'console-finished.png'),'-dpng','-r100');
    print(BpodSystem.GUIHandles.Figures.DemonFigure,fullfile(outputFolder,'task-finished.png'),'-dpng','-r100');
    fprintf('PASS: full FakeSubject session, replay=%d, saved %s\n', enabled, BpodSystem.Path.CurrentDataFile{1});
    close(BpodSystem.GUIHandles.Figures.DemonFigure);
    addpath(root);
end
end

function driveSession(driver,~)
global BpodSystem ChipmunkSessionTest
% Deleted timers can still have a callback queued during the next GUI startup.
if ~isvalid(driver) || ~isstruct(ChipmunkSessionTest) || ...
        ~isfield(ChipmunkSessionTest,'driver') || ~isequal(driver,ChipmunkSessionTest.driver)
    return
end
try
    timeout = 90;
    if ~isempty(ChipmunkSessionTest.trialLimit), timeout = max(timeout,3*ChipmunkSessionTest.trialLimit); end
    if toc(ChipmunkSessionTest.started) > timeout
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
    if ~isempty(ChipmunkSessionTest.badReplayEnable) && ...
            isfield(BpodSystem.GUIHandles,'ParamEdit') && ...
            isfield(BpodSystem.GUIHandles.ParamEdit,'passiveReplayEnable') && ...
            isgraphics(BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable)
        set(BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable,'String',ChipmunkSessionTest.badReplayEnable);
    end
    state = BpodSystem.Status.CurrentStateName;
    ports = find(BpodSystem.HW.Inputs == 'P');
    ChipmunkSessionTest.centerHeld = BpodSystem.HardwareState.InputState(ports(2)) ~= 0;
    ChipmunkSessionTest.sideHeld = BpodSystem.HardwareState.InputState(ports(1)) ~= 0;
    if ~strcmp(state,ChipmunkSessionTest.lastState)
        if isempty(ChipmunkSessionTest.trialLimit) || ChipmunkSessionTest.trialLimit <= 3
            fprintf('Emulator driver state: %s\n',state);
        elseif isfield(BpodSystem.Data,'nTrials') && mod(BpodSystem.Data.nTrials,100)==0
            fprintf('ENDURANCE_PROGRESS %d\n',BpodSystem.Data.nTrials);
        end
        ChipmunkSessionTest.lastState = state;
    end
    if ~ChipmunkSessionTest.natural && strcmp(BpodSystem.ProtocolSettings.smaAssembler,'PassiveVisualStimSMA') && ...
            strcmp(state,'PlayStimulus') && ...
            isfield(BpodSystem.Data,'TrialSettings') && numel(BpodSystem.Data.TrialSettings) >= 3
        ChipmunkSessionTest.snapshot = BpodSystem.Data;
        set(BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable,'String',num2str(ChipmunkSessionTest.enable));
        ChipmunkSessionTest.stopped = true;
        RunProtocol('Stop');
    elseif strcmp(state,'DemonWaitForCenterFixation')
        if ~ChipmunkSessionTest.natural && isfield(BpodSystem.Data,'TrialSettings') && numel(BpodSystem.Data.TrialSettings) >= 3
            ChipmunkSessionTest.snapshot = BpodSystem.Data;
            set(BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable,'String',num2str(ChipmunkSessionTest.enable));
            ChipmunkSessionTest.stopped = true;
            RunProtocol('Stop');
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
