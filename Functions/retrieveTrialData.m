function retrieveTrialData(RawEvents,TrialsDone,TrialSidesList,trialDelays,reviseChoiceFlag, ModalityRecord,...
    stimulusDuration, stimTrainDuration, categoryBoundary,interStimulusIntervalList,visualIsiList,auditoryIsiList);
% retrieveTrialData(RawEvents,TrialsDone,TrialSidesList,trialDelays,reviseChoiceFlag, ModalityRecord,...
%    stimulusDuration, stimTrainDuration, categoryBoundary,interStimulusIntervalList,visualIsiList,auditoryIsiList);
%
% Add outcome data of the last trial to the data structure in BpodSystem.
% Note that this function has no outputs because all the values are stored
% inside the global variable BpodSystem.Data
%
% INPUTS:
% -RawEvents: The output received from Bpod after running the state machine
%             with all the events, states and timers.
% -TrialsDone: The number of completed trials.
% -TrialSidesList: List of sides assigned for the individual trials,
%                  contains 0 (left) and 1 (right).
% -delays: Struct containing the imposed trial delays. This should contain
%          the following fields: trialStartDelay, preStimDelay, waitTime,
%          stimTrainDuration, postStimDelay.
% -reviseChoiceFlag: Logical value containing true if the animal could
%                    could poke into the other port after chosing the wrong
%                    one at first and still be rewarded.
% -ModalityRecord: The stimulus modality code, 1 = visual, 2 = auditory, 
%                  3 = multi-sensory
% -stimulusDuration: The duration of the individual stimulus event (s)
% -stimTrainDuration: Duration of the stimulus train (s)
% -categoryBoundary
% -interStimulusIntervalList: The list of intervals between the individual
%                             stimuli inside the stim train. The auditory
%                             and visual ISI lists are somewhat redundant
%                             to this input...
% -visualIsiList
% -auditoryIsiList
%
% LO, 5/26/2021, 7/13/2021
%--------------------------------------------------------------------------
global BpodSystem

BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
%This function collects some useful information and puts it into the data
%struct. These include the trial settings, state machine info, events and
%states

%Add the settings used for this trial
BpodSystem.Data.TrialSettings(TrialsDone) = BpodSystem.ProtocolSettings;

%Go first thorugh the demonstrator data
%The side and outcome info
BpodSystem.Data.CorrectSide(TrialsDone) = TrialSidesList(TrialsDone);
BpodSystem.Data.Rewarded(TrialsDone) = ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonReward(1));
BpodSystem.Data.EarlyWithdrawal(TrialsDone) = ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonEarlyWithdrawal(1));

BpodSystem.Data.DidNotChoose(TrialsDone) = 0; %Assume default false
if isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States,'DemonDidNotInitiate') %In the observer fixation training this state does not exist
    if ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonDidNotChoose(1));
        BpodSystem.Data.DidNotChoose(TrialsDone) = 1;
    end
end

BpodSystem.Data.DidNotInitiate(TrialsDone) = 0; %Assume default false
if isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States,'DemonDidNotInitiate') %In the paced version check whether the demonstrator did the trial
    if ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonDidNotInitiate(1))
        BpodSystem.Data.DidNotInitiate(TrialsDone) = 1;
    end
end

%Get simulus related information
BpodSystem.Data.Modality(TrialsDone) = ModalityRecord(TrialsDone);
BpodSystem.Data.StimulusDuration(TrialsDone) = stimulusDuration;
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
if isfield(trialDelays,'trialStartDelay')
    BpodSystem.Data.TrialStartDelay(TrialsDone) = trialDelays.trialStartDelay;
end
if isfield(trialDelays,'interTrialInterval')
 BpodSystem.Data.InterTrialInterval(TrialsDone) = trialDelays.interTrialInterval; %This is redundant in the case of an observer being present
end
BpodSystem.Data.PreStimDelay(TrialsDone) = trialDelays.preStimDelay;
BpodSystem.Data.SetWaitTime(TrialsDone) = trialDelays.waitTime; %This value may update during every loop.
BpodSystem.Data.TotalStimDuration(TrialsDone) = stimTrainDuration;
BpodSystem.Data.PostStimDelay(TrialsDone) = trialDelays.postStimDelay;
BpodSystem.Data.ExtraStimDuration(TrialsDone) = BpodSystem.ProtocolSettings.extraStimDur;

%Compute time spent in center for  each trial with one nose poke in
%and out of the center port.
BpodSystem.Data.ActualWaitTime(TrialsDone) = NaN;
if ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonInitFixation(1)) %A wait time only exists when the demonstrator initiates
    if ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonWaitForResponse(1))
        BpodSystem.Data.ActualWaitTime(TrialsDone) = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonWaitForWithdrawalFromCenter(2) - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonInitFixation(1);
    elseif ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonEarlyWithdrawal(1))
        BpodSystem.Data.ActualWaitTime(TrialsDone) = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonEarlyWithdrawal(1) - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonInitFixation(1);
    end
end
% 
% if isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events,'Port2Out') && isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events,'Port2In')
%     if (numel(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2Out)== 1) && (numel(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2In) == 1)
%         BpodSystem.Data.ActualWaitTime(TrialsDone) = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2Out - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2In;
%     end
% end

ResponseSideRecord = NaN; %Pre-set the response to NaN and change if the trial was valid
if reviseChoiceFlag %Check for the actual response side if the animal can revise its decision
    if ~(BpodSystem.Data.EarlyWithdrawal(TrialsDone) || BpodSystem.Data.DidNotChoose(TrialsDone) || BpodSystem.Data.DidNotInitiate(TrialsDone))
        %Three scenarios where the demonstrator doesn't choose: No
        %initiation, early withdrawal, no choice after waiting.
        %Only if none of them applies execute below
        P1visits = []; P3visits = [];
        if isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events, 'Port1In')
            P1visits = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port1In(find(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port1In > BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonCenterFixationPeriod(1)));
        end
        if isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events, 'Port3In')
            P3visits = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port3In(find(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port3In > BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.DemonCenterFixationPeriod(1)));
        end
        if isempty(P3visits)
            ResponseSideRecord = 0;
        elseif isempty(P1visits)
            ResponseSideRecord = 1;
        else
            ResponseSideRecord = P1visits(1) > P3visits(1); % the case when the animal changes its mind after trying
        end
    else
        ResponseSideRecord = NaN; %If the trial was invalid
    end
    
else %The case where wrong choices are punished
    if ~(BpodSystem.Data.EarlyWithdrawal(TrialsDone) || BpodSystem.Data.DidNotChoose(TrialsDone) || BpodSystem.Data.DidNotInitiate(TrialsDone))
        if (TrialSidesList(TrialsDone)==0 && BpodSystem.Data.Rewarded(TrialsDone)) || (TrialSidesList(TrialsDone)==1 && ~BpodSystem.Data.Rewarded(TrialsDone))
            ResponseSideRecord = 0;
        elseif (TrialSidesList(TrialsDone)==0 && ~BpodSystem.Data.Rewarded(TrialsDone)) || (TrialSidesList(TrialsDone)==1 && BpodSystem.Data.Rewarded(TrialsDone))
            ResponseSideRecord = 1;
        end
    else
        ResponseSideRecord = NaN;
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

%Update the earned reward volume
    if BpodSystem.Data.Rewarded(TrialsDone) == 1 %Only if rewarded, but not necessarily only if correct because of the possibility to revise choice
        if BpodSystem.Data.CorrectSide(TrialsDone) == 0 %The left side was rewarded
            BpodSystem.Data.LeftSideRewardAmount = BpodSystem.Data.LeftSideRewardAmount + BpodSystem.ProtocolSettings.leftRewardVolume;
        elseif BpodSystem.Data.CorrectSide(TrialsDone) == 1 %The left side was rewarded
            BpodSystem.Data.RightSideRewardAmount = BpodSystem.Data.RightSideRewardAmount + BpodSystem.ProtocolSettings.rightRewardVolume;
        end
    end

%And now we check the data for the observer...
if isfield(BpodSystem.ProtocolSettings,'obsID')
  %Extract first the outcome information  
    
    % Set the default case
    BpodSystem.Data.ObsCompletedTrials(TrialsDone) = 0;
    BpodSystem.Data.ObsEarlyWithdrawal(TrialsDone) = 0;
    BpodSystem.Data.ObsDidNotHarvest(TrialsDone) = 0;
 if ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.ObsReward(1))
     BpodSystem.Data.ObsOutcomeRecord(TrialsDone) = 1;
     BpodSystem.Data.ObsCompletedTrials(TrialsDone) = 1;
     BpodSystem.Data.ObsRewardAmount = BpodSystem.Data.ObsRewardAmount + BpodSystem.ProtocolSettings.obsRewardVolume; %Add this here
 elseif ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.ObsEarlyWithdrawal(1))
     BpodSystem.Data.ObsOutcomeRecord(TrialsDone) = -1;
     BpodSystem.Data.ObsEarlyWithdrawal(TrialsDone) = 1;
 elseif ~isnan(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.ObsDidNotHarvest(1))
     BpodSystem.Data.ObsOutcomeRecord(TrialsDone) = 2;
     BpodSystem.Data.ObsDidNotHarvest(TrialsDone) = 1;
 end

 %Next check on the wait time
 BpodSystem.Data.ObsSetWaitTime(TrialsDone) = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.ObsCheckFixationSuccess(1) - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.ObsInitFixation(1); %This is the intervall, in which Teensy will count
 BpodSystem.Data.ObsActualWaitTime(TrialsDone) = min(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.ObserverDeck1_2(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.ObserverDeck1_2 > BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.ObsInitFixation(1))) - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.States.ObsInitFixation(1);
 %Take the first breaking as the start and the first joining as the end of
 %the observer fixation.

 %Finally get the inter-trial intervals, this is important to be able to
 %react when the observer holds up the demonstrator
 if TrialsDone == 1
        BpodSystem.Data.InterTrialInterval(TrialsDone) = NaN;
 else
     BpodSystem.Data.InterTrialInterval(TrialsDone) = BpodSystem.Data.TrialStartTimestamp(TrialsDone) - BpodSystem.Data.TrialStartTimestamp(TrialsDone-1);
 end
end