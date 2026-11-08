function data = passiveReplayFixture()
% Short saved-trial records shared by regression and real Bpod emulator checks.
settings = struct('stimBrightness',1,'stimLoudness',40,'soundCalibrationModelParams',[.01 -2]);
data.TrialSettings = repmat(settings,1,4);
data.TrialSettings(2).stimLoudness = 50;
data.TrialSettings(3).stimBrightness = 2;
data.Modality = [1 2 3 1];
data.StimulusDuration = [.01 .01 .01 .01];
data.ExtraStimDuration = [0 .03 .1 0];
data.InterStimulusIntervalList = {[0 .02 .02],NaN;NaN,[0 .03 .01];[.01 .02 .01],[0 .03 .01];[0 .02 .02],NaN};
data.TrialDelays = repmat(struct('interTrialInterval',.01),1,4);
data.RawEvents.Trial = repmat({struct('States',struct('PlayStimulus',[0 .01]))},1,4);
data.RawEvents.Trial{4}.States.PlayStimulus = [NaN NaN];
end
