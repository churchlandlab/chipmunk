function [sma, trialDelays, reviseChoiceFlag, pacedFlag] = ObserverFixationTrainingSMA(correctSideOnCurrent);
% [sma, trialDelays, reviseChoiceFlag, pacedFlag] = ObserverFixationTrainingSMA(correctSideOnCurrent);
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
% "virtualDemonCorrectRate" and "virtualDemonEarlyWithdrawalRate".
%
% NOTE that this assembler makes a set of assumptions about plausible trial
% delays that are not passed as arguments but that are defined inside this
% function (see first section).
%
% Revision Notes:
% In the revised version the demonstrator starts the trial and only then
% the observer can fixate. This will hopefully reduce the time that the
% observer will have to fixate on the observer deck.
%
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
% LO, 7/8/2021, 10/13/2021, 1/11/2022, 4/10/2022
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
        %RewardValve = 2^0; %left-hand port represents port#0, therefore valve value is 2^0
        %rewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.leftRewardVolume, 1); %second value is Bpod index for the valve
        incorrectPortLED = 'PWM3';
        leftPortAction = 'DemonReward';
        rightPortAction = 'DemonWrongChoice';
    elseif rewardedSide == 1 %the case for right side correct
        %RewardValve = 2^2; %left-hand port represents port#0, therefore valve value is 2^0
        %rewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.rightRewardVolume, 3);
        incorrectPortLED = 'PWM1';
        leftPortAction = 'DemonWrongChoice';
        rightPortAction = 'DemonReward';
    end

else %The dummy case assuming left
    %rewardedSide = 0;
    %RewardValve = 2^0;
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
% Impose a random interval between the trials. In earlier versions this was
% not present for the observer and a random inter trial inerval was only
% imposed on the demonstrator to mimick the time it takes the observer to
% initiate a new trial. In this version of chipmunk where the demonstrator
% initiates and waits for the observer the inter trial interval has two
% functions: it keeps the demonstrator from poking too early when the
% observer can't yet fixate in the observer deck and instructs the observer
% that it can only poke when the demonstrator is already fixating.

% The delay observer initiating and stimulus playing
preStimDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax); %The demonstrator preStimDelay is replaced in the observer

% Introduce some randomness in the required wait time. Here this is
% implemented as maximally 10% of the minimum observation time.
minObsTime = BpodSystem.ProtocolSettings.minObsTime + generate_random_delay(12, 0, BpodSystem.ProtocolSettings.minObsTime*0.1);

% Assign the wait- and reporting time of a virtual demonstrator. This is to
% find the appropriate timing of the go-cue.
if minObsTime  > 1.1 %If the minimal wait time is bigger than the stimulus presentation plus delay time
   postStimDelay = generate_random_delay(1/0.1, 0.01, 1); %set lambda such that the mean is 0.1 : mean = 1/lambda
   waitTime = 1 + postStimDelay; %To mimick the regular wait time with the go-cue
   %This version is different than the previous one in the sense that the
   %go-cue will always occur after 1-1.1 s once the observer has reached
   %wait times greater than 1.1 seconds.
   
else %In case the wait time is shorter than the maximal reporting time deliver the demonstrator go cue randomly
    waitTime =  rand * minObsTime;
    postStimDelay = 0;
end
reportingTime = minObsTime - waitTime;
%The difference between the set minimal observation time and the set wait
%time is designated as the simulated demonstrator reporting time.

%Define a brief delay between the outcome for the demonstrator and
%revealing the fixation success to the observer.
outcomeSeparation = 0;
%In the observer training curretnly no outcomes are presented to the
%observer, therefore we don't need to delay the early withdrawal
%punishment.
% Create the struct to hold the task delays
trialDelays = struct();
trialDelays.trialStartDelay = trialStartDelay;
trialDelays.preStimDelay = preStimDelay;
trialDelays.waitTime = waitTime;
trialDelays.postStimDelay = postStimDelay;
trialDelays.interTrialInterval = interTrialInterval;
trialDelays.reportingTime = reportingTime;
trialDelays.outcomeSeparation = outcomeSeparation;

%--------------------------------------------------------------------------
%% Prepare the simulated outcomes of the demonstrator trial. The rate of correct
% vs incorrect choices and early withdrawals can be set as a parameter in
% the settings. These outcomes are included in the training here because
% they are associated with some sound delivered to the demonstrator that
% the observer has to learn to ignore if it performs the observer task.

%This is outdated in the current version (10/4/2022) where observers learn
%to watch the empty box. 

if rand < BpodSystem.ProtocolSettings.virtualDemonEarlyWithdrawalRate
        earlyWithdrawalTime = (1 - generate_random_delay(10, 0.01, 1)) * waitTime;
        %Randomly draw times of early withdrawal according to how long the
        %virtual demonstrator is supposed to wait. Make withdrawals just at
        %the end of the wait time more likely.
               
    trialOutcome = 'DemonReward'; %Let's just assume the mouse would choose correctly if it stayed
else
    if rand > BpodSystem.ProtocolSettings.virtualDemonCorrectRate
        trialOutcome = 'DemonWrongChoice';
    else
        trialOutcome = 'DemonReward';
    end
    earlyWithdrawalTime = NaN;
end

%--------------------------------------------------------------------------
%% Assemble the state matrix

sma = NewStateMatrix(); %generate a new empty state matrix

sma = AddState(sma, 'Name', 'Sync', ...
    'Timer', 0.1, ...
    'StateChangeCondition', {'Tup','TrialStart'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'BNC2', 1});
%State to send a TTL to the cameras to sync with Bpod. The duration of the
%TTL is set to 0.1 s, thus the lowest frame rate where the stim can can be
%detected on at least one frame is 10 fps.

sma = AddState(sma, 'Name', 'TrialStart', ...
    'Timer', interTrialInterval, ...
    'StateChangeCondition', {'Tup','DemonWaitForCenterFixation'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});
%Start the trial with a delay to allow the observer to finish drinking and
%to get in position for the upcoming trial. Have all the LEDs switched on
%to indicate that no action is currently possible.

sma = AddState(sma, 'Name', 'DemonWaitForCenterFixation', ...
    'Timer', 0, ...
    'StateChangeCondition', {'Tup','DemonInitFixation'},...
    'OutputActions',{'PWM1',255,'PWM3',255,'PWM4',255});
%Placeholder state. In the actual task this state will be the period when
%the demonstrator is allowed to initiate a trial, as indicated by the
%center LED being switched off. It will change when the demonstrator
%successfully pokes into the center port.

sma = AddState(sma, 'Name', 'DemonInitFixation',...
    'Timer',BpodSystem.ProtocolSettings.obsInitiationWindow, ...
    'StateChangeConditions', {'Tup','ObsDidNotInitiate', 'ObserverDeck1_1', 'ObsInitFixation'},...
    'OutputActions', {'SoftCode', 2, 'PWM1', 255, 'PWM3', 255, 'PWM4', 255,});
%This state is the demonstrator waiting for the observer to initiate. First,
%play a sound to indicate possibility to fixate to the observer (SoftCode2). The
%observer has the time obsInitationWindow to break the beam on the observer
%deck otherwise no initiation will be registered. If the observer does it
%successuflly the state machine moves on to PlayStimulus. Note
%that in this paradigm PlayStimulus is just a placeholder, so that the
%analysis generalizes from the Demonstrator tasks. As outputs the initiation tone
%is played to inform the observer that fixation is now possible, the two side LEDs
%and the observer LED are kept on.

sma = AddState(sma, 'Name', 'ObsInitFixation',...
    'Timer',0,...
    'StateChangeConditions', {'Tup','PreStimPeriod'},...
    'OutputActions', {'SoftCode', 255,'ObserverDeck1',30});
%State that registers the fixation of the observer. To indicate successful
%fixation the side LEDs in the demonstrator side are switched off. Bpod
%sends byte 30 to teensy to start counting how often the observer deck beam
%is unbroken.

sma = AddState(sma, 'Name', 'PreStimPeriod',...
    'Timer',preStimDelay,...
    'StateChangeConditions', {'Tup','PlayStimulus'},...
    'OutputActions', {'PWM4', 255});
%Delay between the end of the observer init sound and the playing of the
%stimulus

sma = AddState(sma, 'Name', 'ObsDidNotInitiate',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','PreStimPeriod'},...
    'OutputActions', {'SoftCode', 255,'ObserverDeck1',33});
%Register that the observer did not initiate in the correct time window to
%evaluate observer fixation success later. Bit 33 to teensy signals
%non-initiation and will be treated like unsucessful fixation without
%punishment. Switch off the side LEDs to indicate that stimulus
%presentation starts.

sma = AddState(sma, 'Name', 'PlayStimulus',...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup','DemonCenterFixationPeriod'},...
    'OutputActions', {'PWM4',255});
%Placeholder for the corresponding state in the demonstrator and observer
%tasks with an actual demonstrator, thus no stim is delivered here.
%Also swith off the side LEDs to
%indicate to the observer that the fixation was successful.

if ~isnan(earlyWithdrawalTime) %If this trial has been designated a demonstrator early withdrawal
sma = AddState(sma, 'Name', 'DemonCenterFixationPeriod',...
    'Timer',earlyWithdrawalTime, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM4',255});
else
sma = AddState(sma, 'Name', 'DemonCenterFixationPeriod',...
    'Timer',waitTime, ...
    'StateChangeConditions', {'Tup','DemonGoCue'},...
    'OutputActions', {'PWM4',255});
end
%Period of simulated demonstrator fixation. If successfull move on to go
%cue or get early withdrawal otherwise. Keep the LED in the observer side
%on still.

sma = AddState(sma, 'Name', 'DemonGoCue',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWaitForWithdrawalFromCenter'},...
    'OutputActions', {'SoftCode',3,'PWM4',255});
%After the required time to wait in the center is over a sound is played
%that tells the demonstrator that it can leave the poke now.

sma = AddState(sma, 'Name', 'DemonWaitForWithdrawalFromCenter',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWaitForResponse'},...
    'OutputActions', {'PWM4',255});
%Yet another placeholder state. This is usually the state while the
%demonstrator mouse reacts and pulls its nose out of the center port. Here,
%our virtual mouse does this instantaneously.

sma = AddState(sma, 'Name', 'DemonWaitForResponse',...
    'Timer',reportingTime, ...
    'StateChangeConditions', {'Tup',trialOutcome},...
    'OutputActions', {'PWM4',255});
%This is the period to report the choice by poking into one of the side
%pokes. In this scenario it ends after the reporting time has elapsed with
%a pre-designated outcome. trialOutcome is a string pointing to the next
%possible state: DemonReward or DemonWrongChoice.

sma = AddState(sma,'Name', 'DemonReward',...
    'Timer',outcomeSeparation, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM2',255, incorrectPortLED, 255,'PWM4',255,'ObserverDeck1',31});
%Reward delivery to the demonstrator. First, switch off the stimulus if it
%is still playing (when extraStimTime is big) and then switch the LEDs of
%the incorrect port and the center on, so that the observer understands
%that the observation phase is completed. Keep the LED at the observer
%reward port still on. Finally, send bit 31 to teensy to stop counting the
%beam unbreakings. Ommit actual reward delivery for this training stage.


sma = AddState(sma, 'Name', 'DemonWrongChoice',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWrongChoicePunishment'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'SoftCode',255,'ObserverDeck1',31});
%Wrong choice of the demonstrator leads to stop of the stimulus and
%switching on of all the LEDs. Send 31 to teensy to tell it to stop
%counting.

sma = AddState(sma, 'Name', 'DemonWrongChoicePunishment',...
    'Timer',outcomeSeparation, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});
%Wrong choice punishment of the demonstrator leads to all LEDs being swithed on again
%after terminating the stim signal. Don't play punishment sound for the
%training.
 
sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawalPunishment'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'ObserverDeck1', 31}); 
%In the case of an early withdrawal by the demonstrator we first need to
%terminate the stimulus presentation with SoftCode 255 before delivering
%the punishment sound and timeout. Teensy gets the signal to stop counting
%the observer unbreaking here.

sma = AddState(sma, 'Name', 'DemonEarlyWithdrawalPunishment',...
    'Timer',outcomeSeparation, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255}); 
%Deliver the punisment noise with SoftCode 4. In the observer task
%condition there is no extra timeout for the demonstrator, the mouse just
%misses the chance to obtain reward. The delay added here serves to produce
%a small gap between the outcome from the demonstrator and the observer.
%Don't play the punishment noise here because the observer is only
%training.

sma = AddState(sma, 'Name', 'DemonDidNotChoose',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'ObserverDeck1', 31});
%This state here is unconnected and will never be visited. Yet, it is there
%as a placeholder for the actual observer task.
    
%---Note in this implementation there is no simulatneous reward delivery to
%the demonstrator and the observer since in some pilot experiments that
%seemed not to have been very important.

sma = AddState(sma, 'Name', 'ObsCheckFixationSuccess',...
    'Timer',0, ...
    'StateChangeConditions', {'ObserverDeck1_3','ObsWaitForRewardRetrieval','ObserverDeck1_4','ObsEarlyWithdrawal','ObserverDeck1_5','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'ObserverDeck1',32});
%This is now the state where the observer's fixation success is going to be
%evaluated. Teensy recieves bit 32 telling it to report whether the mouse
%correctly fixated throughout the whole period. If yes event
%ObserverDeck1_3 will be reported if no ObserverDeck1_4 will be sent. If 
%the mouse did not initiate in the first place ObserverDeck1_5 will be
%registered and the trial will end. Note that at this point all the port LEDs are on.

sma = AddState(sma, 'Name', 'ObsWaitForRewardRetrieval',...
    'Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Port4In','ObsReward', 'Tup','ObsDidNotHarvest'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255});
%Switch off the observer reward port LED but keep the ones on the
%demonstrator side on. Give the observer the same amoubnt of time to get to
%the reward port as the demonstrator (timeToChoose).

sma = AddState(sma, 'Name', 'ObsReward',...
    'Timer',obsRewardValveTime, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'ValveState', obsRewardValve,'PWM1',255,'PWM2',255,'PWM3',255});
%Deliver the reward to the observer and finish the trial.

sma = AddState(sma, 'Name', 'ObsDidNotHarvest',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255, 'PWM4', 255});
%If the observer mouse did not retrieve its reward in time the LED in its
%reward port will switch on indicating the end of the trial

sma = AddState(sma, 'Name', 'ObsEarlyWithdrawal',...
    'Timer',BpodSystem.ProtocolSettings.obsEarlyPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode', 6});
%If the observer has broken fixation early it will be punished with a
%noise and an extra time out. In the actual task this may be dropped
%because it might be to frustrating for the demonstrator...

sma = AddState(sma, 'Name', 'FinishTrial',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','>exit'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});
%Finish the trial.

%--------------------------------------------------------------------------
%% Set whether the choice can be revised
reviseChoiceFlag = false;

%% Set whether the demonstrator trials are paced
pacedFlag = false;

end