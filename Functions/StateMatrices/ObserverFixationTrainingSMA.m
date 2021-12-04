function [sma, taskDelays, reviseChoiceFlag, pacedFlag] = ObserverFixationTrainingSMA(correctSideOnCurrent);
% [sma, taskDelays, reviseChoiceFlag, pacedFlag] = ObserverFixationTrainingSMA(correctSideOnCurrent);
%
% SMA assembler function for the fixation training of the observer. During
% this training phase the observer learns to wait on the observer deck and
% retrieve a reward for successfull fixation irrespective of the outcome of
% the demonstrator. Use the minObsTime and -Step to slowly increase the
% fixation time. Above the medianDemonstratorTrialDur the wait duration is 
% randomly generated similar to the wait time for the evidence accumulation.
% Observer early withdrawals are punished with a pink noise tone and a
% a timeout. Here, the demonstrator trial structure sounds are also played
% with the go cue occuring at a random time after the demon trial start cue.
% The rate of occurence of the different outcomes is defined by
% "simulatedCorrectRate" and "simulatedEarlyWithdrawalRate".
%
% NOTE that this assembler makes a set of assumptions about plausible trial
% delays that are not passed as arguments but that are defined inside this
% function (see first section). 

% INPUTS (optional): -correctSideOnCurrent: The side designated to be
%                                           rewarded during the current trial
%                                           if chosen.
%
% Outputs: - sma: The state machine to be sent to Bpod to run the trial.
%          - taskDelays: A struct containing the pre-stimulus delay and the
%                        wait time generated for the current trial.
%          -reviseChoiceFlag: Boolean whether the mouse can change its mind
%                             after first reporting.
%          -pacedFlag: Indicates whether the demonstrator trials are paced
%                      by an observer or virtually (pacedFlag = true) or
%                      whether it can self initiate (pacedFlag = false).
%
% LO, 7/8/2021, 10/13/2021
%-------------------------------------------------------------------------
global BpodSystem

%% Assign parameters that need to be estimated from actual animal data
% This version here is some rough estimate and the parameters will need to
% be refined in the future.
% minVirtualReportingTime = 0.8; %The minimum time assumed it takes an animal to report its choice after the go cue
% maxVirtualReportingTime = 1.6; %The maximum time set the animal requires to report choice
% lambdaVirtualReportingTime = 1; %Shape parameter of the exponential distribution to draw the reporting time from

%medianDemonstratorTrialDur = 3.5; %Median duration from start trial cue to choice report for the demonstrator as estimated from good animals
% 
% minVirtualEarlyWithdrawalTime = 0.01; %Parameters for drawing the early withdrawal times
% maxVirtualEarlyWithdrawalTime = 1 + BpodSystem.ProtocolSettings.initiationWindow; %The window during which the demonstrator can show early withdrawals
% lambdaVirtualEarlyWithdrawalTime = 1/0.8;

%---------------------------------------------------------------------------
%% Valve time and LED assignment
% Click the demonstrator valves to have this feedback already
if exist('correctSideOnCurrent') && ~isempty(correctSideOnCurrent) %input check
    rewardedSide = correctSideOnCurrent;
    if rewardedSide == 0 %the case for left side correct
        RewardValve = 2^0; %left-hand port represents port#0, therefore valve value is 2^0
        rewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.leftRewardVolume, 1); %second value is Bpod index for the valve
        incorrectPortLED = 'PWM3';
        leftPortAction = 'DemonReward';
        rightPortAction = 'DemonWrongChoice';
    elseif rewardedSide == 1 %the case for right side correct
        RewardValve = 2^2; %left-hand port represents port#0, therefore valve value is 2^0
        rewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.rightRewardVolume, 3);
        incorrectPortLED = 'PWM1';
        leftPortAction = 'DemonWrongChoice';
        rightPortAction = 'DemonReward';
    end

else %The dummy case assuming left
    rewardedSide = 0;
    RewardValve = 2^0;
    rewardValveTime = 0;
    incorrectPortLED = 'PWM3';
end

obsRewardValve = 2^3; %Port 4
obsRewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.obsRewardVolume, 4); %second value is Bpod index for the valve

%--------------------------------------------------------------------------
%% Generate the variable trial timers etc.

% Delay 
trialStartDelay = 0; %Possibility to introduce a delay when the observer fixates,
% one may use the pre-stim delay paramters to randomly generate this delay.

interTrialInterval = generate_random_delay(BpodSystem.ProtocolSettings.interTrialDurLambda, BpodSystem.ProtocolSettings.interTrialDurMin, BpodSystem.ProtocolSettings.interTrialDurMax);
% Impose a random interval between the trials. This is thought to be
% instructive for the observer 

% The delay between demonstrator poking and stimulus playing
preStimDelay = 0; %The demonstrator preStimDelay is replaced in the observer
% task by the time to the observer needs to initiate.

% Assign the wait- and reporting time of a virtual demonstrator. This is to
% find the appropriate timing of the go-cue.
if BpodSystem.ProtocolSettings.minObsTime  > 1.1 %If the minimal wait time is bigger than the stimulus presentation plus delay time
   postStimDelay = generate_random_delay(1/0.1, 0.01, 1); %set lambda such that the mean is 0.1 : mean = 1/lambda
   waitTime = 1 + postStimDelay; %To mimick the regular wait time with the go-cue
   %This version is different than the previous one in the sense that the
   %go-cue will always occur after 1-1.1 s once the observer has reached
   %wait times greater than 1.1 seconds.
   
else %In case the wait time is shorter than the maximal reporting time deliver the  demonstrator go cue randomly
    waitTime =  rand * BpodSystem.ProtocolSettings.minObsTime;
    postStimDelay = 0;
end
reportingTime = BpodSystem.ProtocolSettings.minObsTime - waitTime;
%The difference between the set minimal observation time and the set wait
%time is designated as the simulated demonstrator reporting time.


% Create the struct to hold the task delays
taskDelays = struct();
taskDelays.trialStartDelay = trialStartDelay;
taskDelays.preStimDelay = preStimDelay;
taskDelays.waitTime = waitTime;
taskDelays.postStimDelay = postStimDelay;
taskDelays.interTrialInterval = interTrialInterval;
taskDelays.reportingTime = reportingTime;

%--------------------------------------------------------------------------
%% Prepare the simulated outcomes of the demonstrator trial. The rate of correct
% vs incorrect choices and early withdrawals can be set as a parameter in
% the settings. These outcomes are included in the training here because
% they are associated with some sound delivered to the demonstrator that
% the observer has to learn to ignore if it performs the observer task.

if rand < BpodSystem.ProtocolSettings.simulatedEarlyWithdrawalRate
        earlyWithdrawalTime = (1 - generate_random_delay(10, 0.01, 1)) * waitTime;
        %Randomly draw times of early withdrawal according to how long the
        %virtual demonstrator is supposed to wait. Make withdrawals just at
        %the end of the wait time more likely.
               
    trialOutcome = 'DemonReward'; %Let's just assume the mouse would choose correctly if it stayed
else
    if rand > BpodSystem.ProtocolSettings.simulatedCorrectRate
        trialOutcome = 'DemonWrongChoice';
    else
        trialOutcome = 'DemonReward';
    end
    earlyWithdrawalTime = NaN;
end

%--------------------------------------------------------------------------
%% Assemble the state matrix

sma = NewStateMatrix(); %generate a new empty state matrix

sma = AddState(sma, 'Name', 'TrialStart', ...
    'Timer', 0, ...
    'StateChangeCondition', {'Tup','DemonInitFixation'},...
    'OutputActions',{'PWM1',255,'PWM3',255,'PWM4',255});
%Switch on the side LEDs only to indicate that the demonstrator can
%initiate a trial now. Transition here directly to the demonstrator
%initiating instead of waiting for it to happen...

sma = AddState(sma, 'Name', 'DemonInitFixation','Timer',BpodSystem.ProtocolSettings.obsInitiationWindow, ...
    'StateChangeConditions', {'Tup','ObsDidNotInitiate', 'Observer_Deck1_1', 'PlayStimulus'},...
    'OutputActions', {'SoftCode', 2, 'PWM1', 255, 'PWM3', 255, 'PWM4', 255,'ObserverDeck1',30});
%This state is the demonstrator waiting for the observer to initiate. The
%observer has the time obsInitationWindow to break the beam on the observer
%deck otherwise no initiation will be registered. If the observer does it
%successuflly the statemachine moves on to PlayStimulus. Note
%that in this paradigm PlayStimulus is just a placeholder, so that the
%analysis generalizes from the Demonstrator tasks. As outputs the initiation tone
% is played to inform the observer that fixation is now possible, the two side LEDs
%and the observer LED are kept on and teensy gets the signal to count
%the observer deck beam breaks.

sma = AddState(sma, 'Name', 'ObsDidNotInitiate','Timer',0, ...
    'StateChangeConditions', {'Tup','PlayStimulus'},...
    'OutputActions', {'PWM4', 255,'ObserverDeck1',33});
%Register that the observer did not initiate in the correct time window to
%evaluate observer fixation success later. Bit 33 to teensy signals
%non-initiation and will be treated like unsucessful fixation without
%punishment. Switch off the side LEDs to indicate that stimulus
%presentation starts.

sma = AddState(sma, 'Name', 'PlayStimulus','Timer', 0, ...
    'StateChangeConditions', {'Tup','DemonCenterFixationPeriod'},...
    'OutputActions', {'PWM4',255});
%Placeholder for the corresponding state in the demonstrator and observer
%tasks with an actual demonstrator.

if ~isnan(earlyWithdrawalTime) %If this trial has been designated a demonstrator early withdrawal
sma = AddState(sma, 'Name', 'DemonCenterFixationPeriod','Timer',earlyWithdrawalTime, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM4',255});
else
sma = AddState(sma, 'Name', 'DemonCenterFixationPeriod','Timer',waitTime, ...
    'StateChangeConditions', {'Tup','DemonGoCue'},...
    'OutputActions', {'PWM4',255});
end
%Period of simulated demonstrator fixation. If successfull move on to go
%cue or get early withdrawal otherwise. Keep the LED in the observer side
%one still.


if ~isnan(earlyWithdrawalTime) %Refering to the time to early withdrawal of a simulated demonstrator   
sma = AddState(sma, 'Name', 'DemonInitFixation','Timer',earlyWithdrawalTime, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode', 2, 'PWM4',255, 'ObserverDeck1',30}); %Send the trial initiaton cue and tell teensy to start looking at observer beam break
else
    sma = AddState(sma, 'Name', 'DemonInitFixation','Timer',BpodSystem.ProtocolSettings.obsInitiationWindow, ...
    'StateChangeConditions', {'Tup','DemonGoCue'},...
    'OutputActions', {'SoftCode',2,'PWM4',255,'ObserverDeck1',30});
end



if ~isnan(earlyWithdrawalTime) %Refering to the time to early withdrawal of a simulated demonstrator   
sma = AddState(sma, 'Name', 'DemonInitFixation','Timer',earlyWithdrawalTime, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode', 2, 'PWM4',255, 'ObserverDeck1',30}); %Send the trial initiaton cue and tell teensy to start looking at observer beam break
else
    sma = AddState(sma, 'Name', 'DemonInitFixation','Timer',waitTime, ...
    'StateChangeConditions', {'Tup','DemonGoCue'},...
    'OutputActions', {'SoftCode',2,'PWM4',255,'ObserverDeck1',30});
end

sma = AddState(sma, 'Name', 'DemonGoCue','Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWaitForWithdrawalFromCenter'},...
    'OutputActions', {'SoftCode',3,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonWaitForWithdrawalFromCenter','Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWaitForResponse'},...
    'OutputActions', {'SoftCode',3,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonWaitForResponse','Timer',reportingTime, ...
        'StateChangeConditions', {'Tup',trialOutcome},...
        'OutputActions', {'PWM4',255});

sma = AddState(sma,'Name', 'DemonReward','Timer',rewardValveTime, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'ValveState', RewardValve,'PWM2',255,incorrectPortLED,255, 'ObserverDeck1', 31});
% Switch the lights on in the center and the incorrect port and leave the
% correct one off, send "Stop counting" (31) to Teensy

sma = AddState(sma, 'Name', 'DemonWrongChoice','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255, 'SoftCode', 5, 'ObserverDeck1', 31});
 
sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255, 'SoftCode', 4, 'ObserverDeck1', 31}); 
% Play the punishment sound and send stop counting to teensy, switch on all
% the LEDs.

if BpodSystem.ProtocolSettings.simultaneousRewardDelivery % For training one may want to click the observer valve already to form an association
    sma = AddState(sma, 'Name', 'ObsCheckFixationSuccess','Timer',0, ...
    'StateChangeConditions', {'ObserverDeck1_3','ObsRewardDelivery','ObserverDeck1_4','ObsEarlyWithdrawal'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'ObserverDeck1',32});

sma = AddState(sma, 'Name', 'ObsRewardDelivery','Timer',obsRewardValveTime, ...
    'StateChangeConditions', {'Tup','ObsWaitForRewardRetrieval'},...
    'OutputActions', {'ValveState', obsRewardValve,'PWM1',255,'PWM2',255,'PWM3',255});

sma = AddState(sma, 'Name', 'ObsWaitForRewardRetrieval','Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Port4In','ObsReward', 'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255});
% Use the time to choose from the demonstrator here to define how long the
% observer may take to harvest its reward.

sma = AddState(sma, 'Name', 'ObsReward','Timer',obsRewardValveTime, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255}); %Dummy state to indicate the harvesting, delivery occurs earlier.

else   
sma = AddState(sma, 'Name', 'ObsCheckFixationSuccess','Timer',0, ...
    'StateChangeConditions', {'ObserverDeck1_3','ObsWaitForRewardRetrieval','ObserverDeck1_4','ObsEarlyWithdrawal'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'ObserverDeck1',32});

sma = AddState(sma, 'Name', 'ObsWaitForRewardRetrieval','Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Port4In','ObsReward', 'Tup','ObsDidNotHarvest'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255});
% Use the time to choose from the demonstrator here to define how long the
% observer may take to harvest its reward.

sma = AddState(sma, 'Name', 'ObsReward','Timer',obsRewardValveTime, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'ValveState', obsRewardValve,'PWM1',255,'PWM2',255,'PWM3',255});
end

 sma = AddState(sma, 'Name', 'ObsEarlyWithdrawal','Timer',BpodSystem.ProtocolSettings.obsEarlyPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode', 6});

sma = AddState(sma, 'Name', 'ObsDidNotHarvest','Timer',0, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255, 'PWM4', 255});

sma = AddState(sma, 'Name', 'FinishTrial','Timer',0, ...
    'StateChangeConditions', {'Tup','>exit'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255});

%--------------------------------------------------------------------------
%% Set whether the choice can be revised
reviseChoiceFlag = false;

%% Set whether the demonstrator trials are paced
pacedFlag = true;

end