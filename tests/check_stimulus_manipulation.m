function check_stimulus_manipulation()
% Dim/long selection without mutating session defaults; saved values drive replay.
root = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
global BpodSystem
assert(isempty(BpodSystem), 'Run this check in a fresh MATLAB session, before starting Bpod.');
oldBpod = BpodSystem;
cleanup = onCleanup(@() restore(oldPath, oldBpod)); %#ok<NASGU>
addpath(genpath(fullfile(root, 'Functions')));
BpodSystem = struct('ProtocolSettings', struct('stimBrightness', 100), 'GUIHandles', struct(), ...
    'Data', struct());
ensureStimulusManipulationSettings();
assert(strcmp(BpodSystem.ProtocolSettings.manipPreset, 'standard'));

BpodSystem.ProtocolSettings.manipFractionPercent = 100;
rng(1);
standard = resolveTrialStimulusParams(4);
assert(~standard.manipulated && standard.brightness == 100);
assert(standard.stimulusDuration == 0.015 && standard.minInterval == 0.025);

BpodSystem.ProtocolSettings.manipPreset = 'dim';
rng(1);
dimEasy = resolveTrialStimulusParams(4);
rng(1);
dimHard = resolveTrialStimulusParams(20);
ineligible = resolveTrialStimulusParams(12);
assert(dimEasy.manipulated && dimEasy.brightness == 30 && dimEasy.stimulusDuration == 0.015);
assert(dimHard.manipulated && dimHard.brightness == 30);
assert(~ineligible.manipulated && ineligible.brightness == 100);
assert(BpodSystem.ProtocolSettings.stimBrightness == 100);

BpodSystem.ProtocolSettings.isPoissonStim = 0;
try
    resolveTrialStimulusParams(4);
    error('Test:ExpectedError', 'A manipulation with the two-interval generator must be rejected.');
catch ME
    assert(strcmp(ME.identifier, 'chipmunk_solo:ManipulationGenerator'));
end
BpodSystem.ProtocolSettings.manipPreset = 'standard';
resolveTrialStimulusParams(4);
BpodSystem.ProtocolSettings.isPoissonStim = 1;

BpodSystem.ProtocolSettings.manipPreset = 'long';
BpodSystem.ProtocolSettings.manipEligibleRates = 4;
rng(1);
longEasy = resolveTrialStimulusParams(4);
longOther = resolveTrialStimulusParams(20);
assert(longEasy.manipulated && longEasy.stimulusDuration == 0.075 && longEasy.minInterval == 0.125);
assert(longEasy.brightness == 100);
assert(~longOther.manipulated && longOther.stimulusDuration == 0.015);

% 75/125 ms only tiles 5 bins; 20 Hz is eligible but cannot be built.
BpodSystem.ProtocolSettings.manipEligibleRates = [4 20];
rng(1);
longTooFast = resolveTrialStimulusParams(20);
rng(1);
longFits = resolveTrialStimulusParams(4);
assert(~longTooFast.manipulated && longTooFast.stimulusDuration == 0.015);
assert(longFits.manipulated && longFits.stimulusDuration == 0.075);

BpodSystem.ProtocolSettings.manipPreset = 'equalized';
BpodSystem.ProtocolSettings.visEventRateList = [4 12 20];
BpodSystem.ProtocolSettings.audEventRateList = [4 12 20];
BpodSystem.ProtocolSettings.multEventRateList = [4 12 20];
eqEasy = resolveTrialStimulusParams(4);
eqMid = resolveTrialStimulusParams(12);
eqHard = resolveTrialStimulusParams(20);
assert(eqEasy.manipulated && strcmp(eqEasy.kind, 'equalized'));
assert(eqEasy.brightness == 100 && eqEasy.stimulusDuration == 0.015);
assert(abs(eqMid.brightness - 100*4/12) < 1e-9);
assert(eqHard.brightness == 20);
assert(abs(4*eqEasy.brightness - 20*eqHard.brightness) < 1e-9);
assert(BpodSystem.ProtocolSettings.stimBrightness == 100);

[combos, labels] = longPulseCombinations();
assert(isequal(combos(:,3), 1000 ./ (combos(:,1) + combos(:,2))));
assert(all(mod(1000, combos(:,1) + combos(:,2)) == 0));
assert(all(abs(combos(:,1) ./ combos(:,2) - 15/25) < 1e-9));
assert(numel(labels) == size(combos, 1));

% Snapshot the values used; later GUI edits must not change replay.
fs = 192000;
isi = [0 0.1 0.1];
data.TrialSettings = BpodSystem.ProtocolSettings;
data.TrialSettings.stimBrightness = dimEasy.brightness;
data.Modality = 1;
data.StimulusDuration = dimEasy.stimulusDuration;
data.ExtraStimDuration = 0;
data.InterStimulusIntervalList = {isi, NaN};
BpodSystem.Data = data;
expected = createVisualStimSignal(isi, fs, 30, 0.015);
BpodSystem.ProtocolSettings.stimBrightness = 100;
BpodSystem.ProtocolSettings.manipDimBrightness = 1;
actual = rebuildTrialStimSignals(1, fs);
assert(isequal(actual(1, 1:numel(expected)), expected));
assert(~isequal(expected, createVisualStimSignal(isi, fs, 100, 0.015)));

fig = figure('Visible', 'off');
figCleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
BpodSystem.GUIHandles.ParamEdit.manipPreset = uicontrol(fig, 'Style', 'popupmenu', ...
    'String', {'Standard', 'Dim flashes', 'Long pulses'}, 'Value', 2);
BpodSystem.GUIHandles.ParamEdit.manipDimBrightness = uicontrol(fig, 'Style', 'edit', 'String', '20');
BpodSystem.GUIHandles.ParamEdit.manipFractionPercent = uicontrol(fig, 'Style', 'edit', 'String', '40');
s = DemonstratorFigure('update', BpodSystem.ProtocolSettings);
assert(strcmp(s.manipPreset, 'dim'));
assert(s.manipDimBrightness == 20 && s.manipFractionPercent == 40);

BpodSystem.Data = struct('nTrials', 3);
mergeSettingsNotes();
assert(isfield(BpodSystem.Data,'Notes') && isempty(BpodSystem.Data.Notes));
old = s;
s.manipPreset = 'long';
s.manipEligibleRates = 4;
s.propLeft = 0.3;
BpodSystem.GUIHandles.ParamEdit = struct();
BpodSystem.GUIHandles.ParamEdit.manipPreset = uicontrol(fig,'Style','popupmenu', ...
    'String',{'Standard','Dim flashes','Long pulses'},'Value',3);
BpodSystem.GUIHandles.ParamEdit.manipEligibleRates = uicontrol(fig,'Style','edit','String','4');
BpodSystem.GUIHandles.ParamEdit.propLeft = uicontrol(fig,'Style','edit','String','0.3');
note = settingsChangeNote(old, s);
assert(contains(note, 'manipPreset dim -> long'));
assert(contains(note, 'propLeft'));
appendTrialNote(4, note);
assert(BpodSystem.Data.nTrials == 3, 'Appending a note must preserve active data.');
assert(contains(BpodSystem.Data.SettingsNotes{4}, 'manipPreset dim -> long'));
appendTrialNote(4, 'manual');
mergeSettingsNotes();
assert(contains(BpodSystem.Data.Notes{4}, 'manipPreset dim -> long'));
assert(contains(BpodSystem.Data.Notes{4}, 'manual'));

settings = load(fullfile(root,'Experiments','MultipleModalitiesTask.mat'));
BpodSystem.ProtocolSettings = settings.ProtocolSettings;
BpodSystem.ProtocolSettings.demonID = 'FakeSubject';
BpodSystem.ProtocolSettings.demonWeight = 25;
BpodSystem.ProtocolSettings.baseWait = 0.5;
BpodSystem.Data = struct('OutcomeRecord',[],'ValidTrials',[],'CorrectResponse',[], ...
    'EarlyWithdrawal',[],'DidNotChoose',[],'LeftSideRewardAmount',0,'RightSideRewardAmount',0);
ensurePassiveReplaySettings();
ensureStimulusManipulationSettings();
DemonstratorFigure('init');
figCleanup2 = onCleanup(@() close(BpodSystem.GUIHandles.Figures.DemonFigure)); %#ok<NASGU>
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipNormalPulseMs,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipNormalGapMs,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipDimBrightness,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipEligibleRates,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipLongCombo,'Enable'),'off'));
set(BpodSystem.GUIHandles.ParamEdit.manipPreset,'Value',2);
cb = get(BpodSystem.GUIHandles.ParamEdit.manipPreset,'Callback');
feval(cb, BpodSystem.GUIHandles.ParamEdit.manipPreset, []);
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipDimBrightness,'Enable'),'on'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipEligibleRates,'Enable'),'on'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipLongCombo,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipNormalPulseMs,'Enable'),'off'));
set(BpodSystem.GUIHandles.ParamEdit.manipPreset,'Value',3);
feval(cb, BpodSystem.GUIHandles.ParamEdit.manipPreset, []);
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipLongCombo,'Enable'),'on'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipNormalPulseMs,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipDimBrightness,'Enable'),'off'));
set(BpodSystem.GUIHandles.ParamEdit.manipPreset,'Value',4);
feval(cb, BpodSystem.GUIHandles.ParamEdit.manipPreset, []);
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipEligibleRates,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipFractionPercent,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipDimBrightness,'Enable'),'off'));
assert(strcmp(get(BpodSystem.GUIHandles.ParamEdit.manipLongCombo,'Enable'),'off'));
s = DemonstratorFigure('update', BpodSystem.ProtocolSettings);
assert(strcmp(s.manipPreset, 'equalized'));
assert(s.manipLongPulseMs == 75 && s.manipLongGapMs == 125);
assert(~isfield(s, 'manipLongCombo'));
BpodSystem.Path.Settings = [tempname '.mat'];
saveCleanup = onCleanup(@() delete(BpodSystem.Path.Settings));
set(BpodSystem.GUIHandles.ParamEdit.manipPreset,'Value',2);
set(BpodSystem.GUIHandles.ParamEdit.manipDimBrightness,'String','17');
button = findall(BpodSystem.GUIHandles.Figures.DemonFigure,'String','Save settings');
cb = get(button,'Callback');
feval(cb,button,[]);
saved = load(BpodSystem.Path.Settings);
assert(saved.ProtocolSettings.manipDimBrightness == 17);
assert(strcmp(saved.ProtocolSettings.manipPreset,'dim'));
assert(BpodSystem.ProtocolSettings.manipDimBrightness ~= 17, 'Save should leave current trial settings unchanged until Update.');
disp('PASS: stimulus manipulation selection, saved-trial replay, GUI update, notes, field enable');
end

function restore(oldPath, oldBpod)
global BpodSystem
path(oldPath);
BpodSystem = oldBpod;
end
