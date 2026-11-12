function check_chipmunk_replay_session(outputFolder, experiments, cameraConfig, trialLimit)
% Full FakeSubject sessions: three trials then Stop, or trialLimit trials to natural completion.
% The first session runs without replay, the rest with replay switched on at Stop.
% Run in a fresh, idle Bpod emulator, or on an idle real Bpod with
% CHIPMUNK_REAL_BPOD_CHECK=1.
if nargin < 4
    trialLimit = [];
end
if nargin < 3
    cameraConfig = '';
end
if nargin < 2
    experiments = {'VisualTask', 'MultipleModalitiesTask', 'VisualTask'};
end
global BpodSystem ChipmunkSessionTest
assert(BpodSystem.Status.BeingUsed == 0 && (BpodSystem.EmulatorMode == 1 || strcmp(getenv('CHIPMUNK_REAL_BPOD_CHECK'), '1')), ...
    'Run in an idle Bpod emulator, or set CHIPMUNK_REAL_BPOD_CHECK=1 for a real Bpod.');
natural = ~isempty(trialLimit);
for session = 1:numel(experiments)
    enabled = session > 1;
    experiment = experiments{session};
    overrides = struct('passiveReplayEnable',0); % Enabled only by editing the controls at Stop.
    if ~isempty(cameraConfig)
        config = jsondecode(fileread(cameraConfig));
        overrides.labcamsConfig = cameraConfig;
        overrides.labcamsAddress = sprintf('127.0.0.1:%d',config.server_port);
    end
    timeout = 90;
    if natural && trialLimit > 3 % Endurance: shortest holds.
        overrides.minWaitTime = .001;
        overrides.preStimDelayMin = .001;
        overrides.preStimDelayMax = .001;
        overrides.interTrialDurMin = 0;
        overrides.interTrialDurMax = 0;
        overrides.extraStimDur = 0;
        timeout = max(timeout,3*trialLimit);
    end
    ChipmunkSessionTest = struct('enable',enabled,'natural',natural,'snapshot',struct());
    [data,file] = runEmulatorSession(outputFolder,experiment,overrides,@act, ...
        'trialLimit',trialLimit,'timeout',timeout);
    assert(ChipmunkSessionTest.stopped || natural,'Driver did not reach active Stop.');
    expectedTrials = 3;
    if natural, expectedTrials = trialLimit; end
    assert(numel(data.Modality) == expectedTrials);
    assert(all(data.ValidTrials == 1));
    if natural
        assert(~isfield(data,'StoppedTrialPulse'));
    else
        % Stop cut the fourth trial short: its Sync pulse follows the three saved trials.
        assert(data.StoppedTrialPulse == 3);
        fields = {'Modality','TrialSettings','RawEvents','InterStimulusIntervalList'};
        for k = 1:numel(fields)
            assert(isequaln(data.(fields{k}),ChipmunkSessionTest.snapshot.(fields{k})));
        end
    end
    if ~isempty(cameraConfig)
        assert(strcmp(data.TrialSettings(1).labcamsConfig,cameraConfig));
    end
    [taskFolder,taskName] = fileparts(file);
    passiveFile = fullfile(fileparts(taskFolder),'chipmunk_passive',[taskName '.mat']);
    if enabled
        assert(data.PassiveReplay.nCompleted == 3 && strcmp(data.PassiveReplay.status,'completed'));
        passive = load(passiveFile);
        assert(isequaln(passive.PassiveReplay,data.PassiveReplay),'Passive dataset copy differs from the task file.');
    else
        assert(~isfield(data,'PassiveReplay'));
        assert(~exist(passiveFile,'file'),'Disabled replay wrote a passive dataset.');
    end
    assert(BpodSystem.Status.BeingUsed == 0);
    assert(isequal(get(BpodSystem.GUIHandles.RunButton,'CData'),BpodSystem.GUIData.GoButton), ...
        'Bpod console still displays Pause after session/replay completion.');
    assert(BpodSystem.Status.InStateMatrix == 0 && BpodSystem.Status.Live == 0);
    assert(strcmp(get(BpodSystem.GUIHandles.DemonStartButton,'String'),'Finished') && ...
        strcmp(get(BpodSystem.GUIHandles.DemonStartButton,'Enable'),'off'));
    assert(~isfield(BpodSystem.PluginObjects,'SoundServer'));
    fprintf('PASS: full FakeSubject session, replay=%d, saved %s\n', enabled, file);
    close(BpodSystem.GUIHandles.Figures.DemonFigure);
end
end

function act(state,nDone,held)
global BpodSystem ChipmunkSessionTest
if strcmp(state,'DemonWaitForCenterFixation')
    if ~ChipmunkSessionTest.natural && nDone >= 3
        ChipmunkSessionTest.snapshot = BpodSystem.Data;
        set(BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable,'String',num2str(ChipmunkSessionTest.enable));
        ChipmunkSessionTest.stopped = true;
        RunProtocol('Stop');
    elseif held(1)
        ManualOverride('IP',1);
    elseif ~held(2)
        ManualOverride('IP',2);
    end
elseif strcmp(state,'DemonWaitForWithdrawalFromCenter') && held(2)
    ManualOverride('IP',2);
elseif strcmp(state,'DemonWaitForResponse') && ~held(1)
    ManualOverride('IP',1);
end
end
