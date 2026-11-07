function check_passive_replay()
% Regression checks without Bpod hardware. Runtime doubles are not an emulator.
root = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
oldFolder = pwd;
global BpodSystem ReplayTest
assert(isempty(BpodSystem), 'Run regression checks in a fresh MATLAB session, before starting Bpod.');
oldBpod = BpodSystem;
cleanup = onCleanup(@() restore(oldPath, oldFolder, oldBpod));
addpath(genpath(fullfile(root, 'Functions')));
data = passiveReplayFixture();
BpodSystem = struct('Data', data, 'ProtocolSettings', data.TrialSettings(1), 'GUIHandles', struct(), ...
    'Status', struct('BeingUsed', 0));
ensurePassiveReplaySettings();
fs = 192000;

% Current settings must not affect either saved source trial.
for source = 1:3
    rng(9);
    expected = rebuildTrialStimSignals(source, fs);
    BpodSystem.ProtocolSettings.stimBrightness = 100;
    BpodSystem.ProtocolSettings.stimLoudness = 100;
    BpodSystem.ProtocolSettings.soundCalibrationModelParams = [1 1];
    rng(9);
    actual = rebuildTrialStimSignals(source, fs);
    assert(isequal(expected, actual));
    settings = data.TrialSettings(source);
    if source == 1 || source == 3
        visual = createVisualStimSignal(data.InterStimulusIntervalList{source,1}, fs, settings.stimBrightness, .01);
        assert(isequal(actual(1,1:numel(visual)), visual));
    end
    if source == 2 || source == 3
        rng(9);
        auditory = createAuditoryStimSignal(data.InterStimulusIntervalList{source,2}, fs, .01, ...
            'whiteNoise + envelope', settings.stimLoudness, 10, settings.soundCalibrationModelParams);
        assert(isequal(actual(2,1:numel(auditory)), auditory));
    end
end

% A train shorter than its nominal duration used to under-allocate repetitions.
short = [1:7; 8:14];
for extra = [0 .49/fs .51/fs 7/fs 8/fs 21/fs 1]
    extended = extendStimulusTrain(short, extra, fs);
    n = round(extra*fs);
    assert(size(extended,2) == 7+n);
    assert(isequal(extended(:,1:7), short));
    if n > 0
        assert(isequal(extended(:,8:end), short(:,mod(0:n-1,7)+1)));
    end
end
BpodSystem.Data.TrialSettings = rmfield(data.TrialSettings, 'stimBrightness');
mustFail(@() rebuildTrialStimSignals(1,fs));
BpodSystem.Data = data;
BpodSystem.Data.InterStimulusIntervalList{1,1} = NaN;
mustFail(@() rebuildTrialStimSignals(1,fs));
BpodSystem.Data = data;

% Real graphics controls, including edits made without clicking Update.
fig = figure('Visible','off');
figCleanup = onCleanup(@() delete(fig));
BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable = uicontrol(fig,'Style','edit','String','1');
BpodSystem.GUIHandles.ParamEdit.passiveReplayFraction = uicontrol(fig,'Style','edit','String','0.5');
BpodSystem.GUIHandles.ParamEdit.passiveReplayOrder = uicontrol(fig,'Style','edit','String','random');
syncPassiveReplaySettingsFromGui();
assert(BpodSystem.ProtocolSettings.passiveReplayEnable == 1);
assert(BpodSystem.ProtocolSettings.passiveReplayFraction == .5);
assert(strcmp(BpodSystem.ProtocolSettings.passiveReplayOrder,'random'));
BpodSystem.GUIHandles = struct();

% Controlled Bpod/sound doubles test lifecycle and persistence, not hardware timing.
cd(tempdir); % Current-folder functions otherwise take precedence over test doubles.
addpath(fullfile(root,'tests','fixtures','passive_replay'), '-begin');
for mode = {'complete','abort','error','empty'}
    ReplayTest = struct('mode',mode{1},'runs',0,'stops',0,'loads',{{}},'matrix',[]);
    BpodSystem.Data = data;
    BpodSystem.ProtocolSettings.passiveReplayEnable = 1;
    BpodSystem.ProtocolSettings.passiveReplayFraction = 1;
    BpodSystem.ProtocolSettings.passiveReplayOrder = 'sequential';
    runPassiveReplaySession(fs,[]);
    result = BpodSystem.Data.PassiveReplay;
    assert(ReplayTest.stops == 1 && BpodSystem.Status.BeingUsed == 0);
    active = rmfield(BpodSystem.Data,'PassiveReplay');
    assert(isequaln(active,data));
    assert(isequal(result.sourceTrialNumbers,[1 2 3])); % Trial 4 never played.
    if strcmp(mode{1},'complete')
        assert(result.nCompleted == 3 && strcmp(result.status,'completed'));
        assert(all(strcmp(result.trialStatus,'completed')));
    elseif strcmp(mode{1},'abort')
        assert(result.nCompleted == 0 && ReplayTest.runs == 1 && strcmp(result.status,'aborted'));
        assert(~isempty(result.rawEvents{1}));
        assert(isequal(result.stoppedPulseAfter,0)); % The aborted replay's pulse follows 0 completed replays.
        assert(strcmp(result.trialStatus{2},'not_started'));
    else
        assert(result.nCompleted == 0 && ReplayTest.runs == 1 && strcmp(result.status,'failed'));
        assert(~isempty(result.errorMessage));
    end
    file = [tempname '.mat'];
    SessionData = BpodSystem.Data;
    save(file,'SessionData');
    saved = load(file);
    delete(file);
    assert(isequaln(saved.SessionData,BpodSystem.Data));
end
% The first onset target includes preparation time and Sync, not a fresh 1-s sleep.
ReplayTest = struct('mode','complete','runs',0,'stops',0,'loads',{{}},'matrix',[]);
BpodSystem.Data = data;
BpodSystem.ProtocolSettings.passiveReplayFraction = 1;
ReplayTest.activeTrialEnd = tic;
pause(.08);
runPassiveReplaySession(fs,[],ReplayTest.activeTrialEnd);
first = ReplayTest.firstMatrix.States;
assert(abs(ReplayTest.firstSentElapsed + first{1}.Timer + first{2}.Timer - 1) < .02);
assert(first{2}.Timer < .9);
assert(BpodSystem.Data.PassiveReplay.interTrialIntervals(2) == data.TrialDelays(2).interTrialInterval);
ReplayTest.mode = 'complete';
for fraction = [0 .5 1]
    BpodSystem.Data = data;
    BpodSystem.ProtocolSettings.passiveReplayFraction = fraction;
    BpodSystem.ProtocolSettings.passiveReplayOrder = 'random';
    runPassiveReplaySession(fs,[]);
    result = BpodSystem.Data.PassiveReplay;
    assert(result.nCompleted == round(3*fraction));
    assert(numel(unique(result.sourceTrialNumbers)) == result.nRequested);
end
BpodSystem.ProtocolSettings.passiveReplayFraction = 1;
BpodSystem.ProtocolSettings.passiveReplayNTrials = 1;
runPassiveReplaySession(fs,[]);
assert(BpodSystem.Data.PassiveReplay.nCompleted == 1);
BpodSystem.Data = struct();
runPassiveReplaySession(fs,[]);
assert(strcmp(BpodSystem.Data.PassiveReplay.status,'skipped'));
% Bad replay edits at natural completion must not prevent the active-data save.
for text = {'', '2', 'NaN'}
    BpodSystem.Data = data;
    BpodSystem.Status.BeingUsed = 0;
    BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable = uicontrol(fig,'Style','edit','String',text{1});
    stops = ReplayTest.stops;
    runPassiveReplaySession(fs,[]);
    assert(strcmp(BpodSystem.Data.PassiveReplay.status,'failed'));
    assert(isequaln(rmfield(BpodSystem.Data,'PassiveReplay'),data));
    assert(ReplayTest.stops == stops+1 && BpodSystem.Status.BeingUsed == 0);
    delete(BpodSystem.GUIHandles.ParamEdit.passiveReplayEnable);
end
BpodSystem.GUIHandles = struct();
BpodSystem.ProtocolSettings.passiveReplayEnable = 0;
BpodSystem.Data = data;
runPassiveReplaySession(fs,[]);
assert(isequaln(BpodSystem.Data,data));
disp('PASS: passive replay reconstruction, controls, selection, abort/error cleanup and MAT round-trip');

end

function restore(oldPath, oldFolder, oldBpod)
global BpodSystem ReplayTest
cd(oldFolder);
path(oldPath);
BpodSystem = oldBpod;
ReplayTest = [];
end

function mustFail(action)
failed = false;
try
    action();
catch
    failed = true;
end
assert(failed,'Expected invalid or missing saved data to fail.');
end
