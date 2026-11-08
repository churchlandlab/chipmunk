function retrieveTrialData(RawEvents,TrialsDone,TrialSidesList,trialDelays,~, ModalityRecord,...
    stimulusDuration, stimTrainDuration, categoryBoundary, interStimulusIntervalList, ...
    visualIsiList, auditoryIsiList, trialBrightness, minInterval)
% Append one trial, preserving legacy field names used by ingestion.
global BpodSystem

BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
%This function collects some useful information and puts it into the data
%struct. These include the trial settings, state machine info, events and
%states

%Add the settings used for this trial. stimBrightness in this snapshot is
%the value that actually built the waveform, not the session default.
trialSettings = BpodSystem.ProtocolSettings;
trialSettings.stimBrightness = trialBrightness;
BpodSystem.Data.TrialSettings(TrialsDone) = trialSettings;

% Choice-state fields are absent in passive sessions.
states = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States;
BpodSystem.Data.CorrectSide(TrialsDone) = TrialSidesList(TrialsDone);
BpodSystem.Data.Rewarded(TrialsDone) = visited(states, 'DemonReward');
BpodSystem.Data.EarlyWithdrawal(TrialsDone) = visited(states, 'DemonEarlyWithdrawal');

BpodSystem.Data.DidNotChoose(TrialsDone) = visited(states, 'DemonDidNotChoose');
BpodSystem.Data.DidNotInitiate(TrialsDone) = false; % Legacy compatibility field; solo trials are self-initiated.

%Get simulus related information
BpodSystem.Data.Modality(TrialsDone) = ModalityRecord(TrialsDone);
BpodSystem.Data.StimulusDuration(TrialsDone) = stimulusDuration;
BpodSystem.Data.StimulusBrightness(TrialsDone) = trialBrightness;
BpodSystem.Data.MinInterval(TrialsDone) = minInterval;
BpodSystem.Data.CategoryBoundary(TrialsDone) = categoryBoundary;
BpodSystem.Data.StimTrainDuration(TrialsDone) = stimTrainDuration;

%Retrieve the inter-stim intervals and the rates
if ModalityRecord(TrialsDone) == 1 %Account for the occurence of uni- and multi-sensory stims
    BpodSystem.Data.InterStimulusIntervalList{TrialsDone,1} = interStimulusIntervalList;
    BpodSystem.Data.InterStimulusIntervalList{TrialsDone,2} = NaN;
    BpodSystem.Data.StimulusRate(TrialsDone,1) = length(interStimulusIntervalList)-1;
    BpodSystem.Data.StimulusRate(TrialsDone,2) = NaN;
elseif ModalityRecord(TrialsDone) == 2
    BpodSystem.Data.InterStimulusIntervalList{TrialsDone,1} = NaN;
    BpodSystem.Data.InterStimulusIntervalList{TrialsDone,2} = interStimulusIntervalList;
    BpodSystem.Data.StimulusRate(TrialsDone,1) = NaN;
    BpodSystem.Data.StimulusRate(TrialsDone,2) = length(interStimulusIntervalList)-1;
else
    BpodSystem.Data.InterStimulusIntervalList{TrialsDone,1} = visualIsiList;
    BpodSystem.Data.InterStimulusIntervalList{TrialsDone,2} = auditoryIsiList;
    BpodSystem.Data.StimulusRate(TrialsDone,1) = length(visualIsiList)-1;
    BpodSystem.Data.StimulusRate(TrialsDone,2) = length(auditoryIsiList)-1;
end

% The delays and wait times

trialDelays.ExtraStimulusDuration = BpodSystem.ProtocolSettings.extraStimDur;
BpodSystem.Data.TrialDelays(TrialsDone) = trialDelays;
if isfield(trialDelays,'interTrialInterval')
 BpodSystem.Data.InterTrialInterval(TrialsDone) = trialDelays.interTrialInterval;
end
BpodSystem.Data.PreStimDelay(TrialsDone) = trialDelays.preStimDelay;
BpodSystem.Data.SetWaitTime(TrialsDone) = trialDelays.waitTime; %This value may update during every loop.
BpodSystem.Data.TotalStimDuration(TrialsDone) = stimTrainDuration;
BpodSystem.Data.PostStimDelay(TrialsDone) = trialDelays.postStimDelay;
BpodSystem.Data.ExtraStimDuration(TrialsDone) = BpodSystem.ProtocolSettings.extraStimDur;

%Compute time spent in center for  each trial with one nose poke in
%and out of the center port.
BpodSystem.Data.ActualWaitTime(TrialsDone) = NaN;
if visited(states, 'DemonInitFixation') %A wait time only exists when the demonstrator initiates
    if visited(states, 'DemonWaitForResponse')
        BpodSystem.Data.ActualWaitTime(TrialsDone) = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonWaitForWithdrawalFromCenter(2) - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonInitFixation(1);
    elseif visited(states, 'DemonEarlyWithdrawal')
        BpodSystem.Data.ActualWaitTime(TrialsDone) = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonEarlyWithdrawal(1) - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonInitFixation(1);
    end
end

ResponseSideRecord = NaN;
if visited(states, 'DemonWaitForResponse') && ...
        ~BpodSystem.Data.EarlyWithdrawal(TrialsDone) && ~BpodSystem.Data.DidNotChoose(TrialsDone)
    ResponseSideRecord = TrialSidesList(TrialsDone);
    if ~BpodSystem.Data.Rewarded(TrialsDone)
        ResponseSideRecord = 1 - ResponseSideRecord;
    end
end

BpodSystem.Data.ResponseSide(TrialsDone) = ResponseSideRecord;
if ~isnan(ResponseSideRecord)
    BpodSystem.Data.CorrectResponse(TrialsDone) = ResponseSideRecord == TrialSidesList(TrialsDone);
else
    BpodSystem.Data.CorrectResponse(TrialsDone) = 0;
end
BpodSystem.Data.ValidTrials(TrialsDone) = ~isnan(ResponseSideRecord);

%Also generate a composite outcome vector containing categorical values
if BpodSystem.Data.CorrectResponse(TrialsDone) == 1
    BpodSystem.Data.OutcomeRecord(TrialsDone) = 1;
elseif BpodSystem.Data.CorrectResponse(TrialsDone) == 0
    BpodSystem.Data.OutcomeRecord(TrialsDone) = 0;
end
if BpodSystem.Data.EarlyWithdrawal(TrialsDone) == 1
    BpodSystem.Data.OutcomeRecord(TrialsDone) = -1;
end
if BpodSystem.Data.DidNotChoose(TrialsDone) == 1
    BpodSystem.Data.OutcomeRecord(TrialsDone) = 2;
end
if BpodSystem.Data.DidNotInitiate(TrialsDone) == 1
    BpodSystem.Data.OutcomeRecord(TrialsDone) = -2;
end

% Accumulate water actually delivered.
if BpodSystem.Data.Rewarded(TrialsDone)
    if TrialSidesList(TrialsDone) == 0
        BpodSystem.Data.LeftSideRewardAmount = BpodSystem.Data.LeftSideRewardAmount + BpodSystem.ProtocolSettings.leftRewardVolume;
    else
        BpodSystem.Data.RightSideRewardAmount = BpodSystem.Data.RightSideRewardAmount + BpodSystem.ProtocolSettings.rightRewardVolume;
    end
end
end

function result = visited(states, name)
result = isfield(states, name) && any(isfinite(states.(name)(:)));
end
