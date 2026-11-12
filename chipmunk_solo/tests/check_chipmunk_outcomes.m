function check_chipmunk_outcomes(outputFolder, modality, correctSide, isPoisson, syncMode)
if nargin < 4, isPoisson = 1; end
if nargin < 5, syncMode = 1; end
% Five full trials: correct, wrong, early pre-stimulus, early stimulus, no choice.
% Run in an idle Bpod emulator; no cameras, hardware rewards or uploads.
global BpodSystem ChipmunkSessionTest
assert(BpodSystem.EmulatorMode == 1 && BpodSystem.Status.BeingUsed == 0);
ChipmunkSessionTest = struct('correctSide',correctSide,'snapshot',struct());
overrides = struct('propLeft',1-correctSide,'propOnlyVisual',double(modality==1), ...
    'propOnlyAuditory',double(modality==2),'isPoissonStim',isPoisson,'syncMultiSensory',syncMode, ...
    'minWaitTime',.2,'timeToChoose',.2,'earlyPunishTimeout',.03,'wrongPunishTimeout',.03, ...
    'preStimDelayMin',.15,'preStimDelayMax',.15, ...
    'passiveReplayEnable',0); % Isolate active outcome and reward accounting.
[data,file] = runEmulatorSession(outputFolder,'MultipleModalitiesTask',overrides,@act);
assert(ChipmunkSessionTest.stopped,'Driver did not reach active Stop.');
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
fprintf('PASS: outcome branches modality=%d correctSide=%d saved %s\n',modality,correctSide,file);
close(BpodSystem.GUIHandles.Figures.DemonFigure);
end

function act(state,nDone,held)
global BpodSystem ChipmunkSessionTest
trial = nDone+1;
if strcmp(state,'DemonWaitForCenterFixation')
    if nDone >= 5
        ChipmunkSessionTest.snapshot = BpodSystem.Data;
        ChipmunkSessionTest.stopped = true;
        RunProtocol('Stop');
    elseif held(1)
        ManualOverride('IP',1);
    elseif held(3)
        ManualOverride('IP',3);
    elseif ~held(2)
        ManualOverride('IP',2);
    end
elseif strcmp(state,'PreStimPeriod') && trial==3 && held(2)
    ManualOverride('IP',2);
elseif strcmp(state,'DemonCenterFixationPeriod') && trial==4 && held(2)
    ManualOverride('IP',2);
elseif strcmp(state,'DemonWaitForWithdrawalFromCenter') && held(2)
    ManualOverride('IP',2);
elseif strcmp(state,'DemonWaitForResponse') && trial<=2 && ~any(held([1 3]))
    side = ChipmunkSessionTest.correctSide;
    if trial==2, side = 1-side; end
    ManualOverride('IP',1+2*side);
end
end
