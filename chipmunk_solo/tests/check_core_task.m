function check_core_task()
% Exercise generator boundaries, passive records, choice outcomes and wait plotting.
global BpodSystem
old = BpodSystem;
oldPath = path;
cleanup = onCleanup(@() restore(old,oldPath));
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(root,'Functions')));
assert(isequal(poissonStimulusTrain(1,.015,.025,0),1));
rng(12);
isi = poissonStimulusTrain(1,.015,.025,20);
assert(numel(isi)==21 && abs(sum(isi)+20*.015-1)<1e-9);
assert(all(isi(2:end-1)>=.025-1e-9));
try
    poissonStimulusTrain(1,.03,.05,4);
    error('Test:ExpectedError','Invalid bins should fail.');
catch ME
    assert(strcmp(ME.identifier,'chipmunk_solo:StimulusBins'));
end
addpath(fullfile(root,'tests','fixtures','trial_data'));
BpodSystem = struct('ProtocolSettings',struct('stimBrightness',100,'extraStimDur',0, ...
    'leftRewardVolume',4,'rightRewardVolume',5), 'Data',struct( ...
    'LeftSideRewardAmount',0,'RightSideRewardAmount',0));
delays = struct('preStimDelay',.1,'waitTime',.6,'postStimDelay',.1,'interTrialInterval',0,'virtualObsInitDelay',0);
passive = struct('States',struct('PlayStimulus',[0 1],'FinishTrial',[1 1]));
retrieveTrialData(passive,1,0,delays,false,1,.015,1,12,[0 1],[],[],100,.025);
assert(~BpodSystem.Data.ValidTrials && isnan(BpodSystem.Data.ResponseSide));
assert(~BpodSystem.Data.Rewarded && isnan(BpodSystem.Data.ActualWaitTime));
choice = struct('States',struct('DemonReward',[1 1.1],'DemonEarlyWithdrawal',[NaN NaN], ...
    'DemonInitFixation',[0 0],'DemonWaitForResponse',[.7 1], ...
    'DemonWaitForWithdrawalFromCenter',[.7 .7]));
retrieveTrialData(choice,2,[0 0],delays,false,[1 1],.015,1,12,[0 1],[],[],100,.025);
assert(BpodSystem.Data.ResponseSide(2)==0 && BpodSystem.Data.ValidTrials(2));
assert(BpodSystem.Data.LeftSideRewardAmount==4);
fig = figure('Visible','off');
figCleanup = onCleanup(@() close(fig));
ax = axes(fig);
WaitTimeDiffPlotDemonstrator(ax,'init',false);
WaitTimeDiffPlotDemonstrator(ax,'refresh',false);
assert(abs(BpodSystem.GUIData.WaitTimeDiffPlotDemonstrator.waitTimeDiff(2))<1e-9, ...
    'Exponential extra wait must not be subtracted twice.');
assert(numel(BpodSystem.GUIHandles.WatiTimeDiffDots.CData)==2);
drawnow;
ax = axes(fig);
OutcomePlotDemonstrator(ax,'init',[0 1 0]);
OutcomePlotDemonstrator(ax,'refresh',4,[0 1 0],[1 0 -1]);
assert(isempty(BpodSystem.GUIHandles.FutureTrialCircle.XData));
assert(all(isnan(BpodSystem.GUIHandles.CurrentTrialCircle.XData)));
axV = axes(fig);
axA = axes(fig);
StimulusPlotDemonstrator(axV,axA,'init',1000,1);
for n = [1020 1000]
    StimulusPlotDemonstrator(axV,axA,'refresh',zeros(2,n));
    lineV = BpodSystem.GUIHandles.StimulusPlotVisualLine;
    lineA = BpodSystem.GUIHandles.StimulusPlotAuditoryLine;
    assert(numel(lineV.XData)==n && numel(lineV.YData)==n);
    assert(numel(lineA.XData)==n && numel(lineA.YData)==n);
    assert(abs(axV.XLim(2)-n/1000)<1e-9 && abs(axA.XLim(2)-n/1000)<1e-9);
end
drawnow;
disp('PASS: zero-rate/invalid-bin generators, passive/choice records and wait-time accounting');
end
function restore(old,oldPath)
global BpodSystem
BpodSystem = old;
path(oldPath);
end
