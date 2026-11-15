function check_chipmunk_manipulation_session(outputFolder, modality, syncMode)
if nargin < 2, modality = 1; end
if nargin < 3, syncMode = 1; end
% FakeSubject emulator: Standard, Dim, Long, then Equalized luminance.
global BpodSystem ChipmunkSessionTest
assert(BpodSystem.EmulatorMode == 1 && BpodSystem.Status.BeingUsed == 0);
root = fileparts(fileparts(mfilename('fullpath')));
overrides = struct('passiveReplayEnable',1,'passiveReplayFraction',1,'passiveReplayNTrials',8, ...
    'passiveReplayOrder','sequential','propOnlyVisual',double(modality == 1), ...
    'propOnlyAuditory',double(modality == 2),'syncMultiSensory',syncMode, ...
    'visEventRateList',[4 20],'audEventRateList',[4 20],'multEventRateList',[4 20],'stimBrightness',100);
ChipmunkSessionTest = struct('phase','standard','applied',false,'beforeReplay',struct(), ...
    'screenshots',fullfile(outputFolder,'gui'));
[~,~] = mkdir(ChipmunkSessionTest.screenshots);
[data,file] = runEmulatorSession(outputFolder,'MultipleModalitiesTask',overrides,@act, ...
    'timeout',180,'beforeStart',@() captureGui('standard'));
assert(ChipmunkSessionTest.stopped, 'Driver did not reach Stop.');
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
notesFile = fullfile(fileparts(file), 'notes.txt');
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
fprintf('PASS: manipulation modality=%d sync=%d session saved %s\n', modality,syncMode,file);
close(BpodSystem.GUIHandles.Figures.DemonFigure);
end

function act(state,nDone,held)
global BpodSystem ChipmunkSessionTest
if strcmp(state,'DemonWaitForCenterFixation')
    if nDone >= 8
        ChipmunkSessionTest.beforeReplay = BpodSystem.Data;
        ChipmunkSessionTest.stopped = true;
        RunProtocol('Stop');
    elseif nDone == 1 && ~ChipmunkSessionTest.applied
        selectPreset(2);
        set(BpodSystem.GUIHandles.ParamEdit.manipFractionPercent,'String','100');
        update();
        ChipmunkSessionTest.applied = true;
        ChipmunkSessionTest.phase = 'dim';
        captureGui('dim');
    elseif nDone == 3 && strcmp(ChipmunkSessionTest.phase,'dim')
        selectPreset(3);
        set(BpodSystem.GUIHandles.ParamEdit.manipEligibleRates,'String','4');
        setRates('4');
        update();
        ChipmunkSessionTest.phase = 'long';
        captureGui('long');
    elseif nDone == 5 && strcmp(ChipmunkSessionTest.phase,'long')
        selectPreset(4);
        setRates('4 20');
        set(BpodSystem.GUIHandles.ParamEdit.propLeft,'String','0');
        update();
        ChipmunkSessionTest.phase = 'equalized';
        captureGui('equalized');
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

function update()
global BpodSystem
callback = get(BpodSystem.GUIHandles.DemonStartButton,'Callback');
feval(callback, BpodSystem.GUIHandles.DemonStartButton, []);
end

function setRates(text)
global BpodSystem
set(BpodSystem.GUIHandles.ParamEdit.visEventRateList,'String',text);
set(BpodSystem.GUIHandles.ParamEdit.audEventRateList,'String',text);
set(BpodSystem.GUIHandles.ParamEdit.multEventRateList,'String',text);
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
