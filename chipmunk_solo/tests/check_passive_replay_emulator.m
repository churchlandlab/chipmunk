function check_passive_replay_emulator(outputFolder)
% Run after Bpod('EMU') in a fresh, idle test MATLAB session. Uses real Bpod/audio.
global BpodSystem ReplayEmulatorTest
assert(~isempty(BpodSystem) && BpodSystem.EmulatorMode == 1, 'Start Bpod in emulator mode first.');
assert(BpodSystem.Status.BeingUsed == 0, 'A session is already running.');
assert(~contains(which('RunStateMatrix'), 'fixtures'), 'Remove test doubles from the MATLAB path.');
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root, fullfile(root,'tests'), genpath(fullfile(root,'Functions')));
mkdir(outputFolder);
cleanup = onCleanup(@stopSound);
watchdog = timer('StartDelay', 30, 'TimerFcn', @(~,~) RunProtocol('Stop'));
watchdogCleanup = onCleanup(@() stopTimer(watchdog));
start(watchdog);
PsychToolboxSoundServer('init');
assert(BpodSystem.PluginObjects.SoundServer.Enabled == 1, 'Emulator audio is unavailable.');
BpodSystem.SoftCodeHandlerFunction = 'replayEmulatorSoftCode';
BpodSystem.GUIHandles.ParamEdit = struct();
data = passiveReplayFixture();
BpodSystem.ProtocolSettings = data.TrialSettings(1);
ensurePassiveReplaySettings();
BpodSystem.ProtocolSettings.passiveReplayEnable = 1;
ReplayEmulatorTest.codes = [];

% Simulate active Stop through Bpod's actual callback, then the main task's path restoration.
RunProtocol('Stop');
addpath(root);
BpodSystem.Data = data;
runPassiveReplaySession(192000, []);
result = BpodSystem.Data.PassiveReplay;
assert(strcmp(result.status,'completed') && result.nCompleted == 3);
assert(isequal(ReplayEmulatorTest.codes,[1 255 1 255 1 255]));
assert(isequal(result.stateNames, {'Sync','InterTrialInterval','PlayStimulus','StopStimulus','FinishTrial'}));
for r = 1:3
    formatted = AddTrialEvents(struct(), result.rawEvents{r});
    states = formatted.RawEvents.Trial{1}.States;
    names = {'Sync','InterTrialInterval','PlayStimulus','StopStimulus','FinishTrial'};
    for k = 1:numel(names)
        assert(all(isfinite(states.(names{k})(:))));
    end
    assert(states.PlayStimulus(1) >= states.InterTrialInterval(1));
    assert(states.StopStimulus(1) >= states.PlayStimulus(1));
end
saveCase('completed');

% A real Bpod Stop callback during ITI and stimulus must abort without another trial.
for phase = {'InterTrialInterval','PlayStimulus'}
    BpodSystem.Data = data;
    BpodSystem.Data.TrialDelays(1).interTrialInterval = .3;
    BpodSystem.Data.ExtraStimDuration(1) = .5;
    ReplayEmulatorTest.codes = [];
    ReplayEmulatorTest.stopState = phase{1};
    trigger = timer('ExecutionMode','fixedSpacing','Period',.02, 'TimerFcn',@stopInState);
    timerCleanup = onCleanup(@() delete(trigger));
    start(trigger);
    runPassiveReplaySession(192000, []);
    stop(trigger);
    assert(strcmp(BpodSystem.Data.PassiveReplay.status,'aborted'));
    assert(BpodSystem.Data.PassiveReplay.nCompleted == 0);
    assert(BpodSystem.Status.BeingUsed == 0);
    saveCase(['abort_' phase{1}]);
    clear timerCleanup
end

% Real reconstruction error, zero selection, random fraction/cap and disabled replay.
BpodSystem.Data = data;
BpodSystem.Data.TrialSettings = rmfield(data.TrialSettings,'stimBrightness');
runPassiveReplaySession(192000,[]);
assert(strcmp(BpodSystem.Data.PassiveReplay.status,'failed'));
saveCase('failed');
for fraction = [0 .5 1]
    BpodSystem.Data = data;
    BpodSystem.ProtocolSettings.passiveReplayFraction = fraction;
    BpodSystem.ProtocolSettings.passiveReplayOrder = 'random';
    runPassiveReplaySession(192000,[]);
    result = BpodSystem.Data.PassiveReplay;
    assert(result.nCompleted == round(3*fraction));
    assert(numel(unique(result.sourceTrialNumbers)) == result.nRequested);
    saveCase(sprintf('random_%g',fraction));
end
BpodSystem.ProtocolSettings.passiveReplayEnable = 0;
BpodSystem.Data = data;
runPassiveReplaySession(192000,[]);
assert(isequaln(data,BpodSystem.Data));
assert(BpodSystem.Status.BeingUsed == 0);
disp('PASS: real Bpod emulator playback, state sequence, Stop in ITI/stimulus, failures, selection, restart and save');

    function saveCase(name)
        SessionData = BpodSystem.Data;
        file = fullfile(outputFolder,[name '.mat']);
        save(file,'SessionData');
        saved = load(file);
        assert(isequaln(saved.SessionData,SessionData));
    end
end

function stopInState(~,~)
global BpodSystem ReplayEmulatorTest
if BpodSystem.Status.BeingUsed && strcmp(BpodSystem.Status.CurrentStateName, ReplayEmulatorTest.stopState)
    RunProtocol('Stop');
end
end

function stopSound()
global BpodSystem
BpodSystem.Status.BeingUsed = 0;
PsychToolboxSoundServer('stopAll');
PsychToolboxSoundServer('Close');
end

function stopTimer(trigger)
stop(trigger);
delete(trigger);
end
