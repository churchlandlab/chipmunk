function [sma, taskDelays, reviseChoiceFlag, pacedFlag] = ObserverTaskSMA(correctSideOnCurrent);
% [sma, taskDelays, reviseChoiceFlag, pacedFlag] = ObserverTaskSMA(correctSideOnCurrent);
%
% SMA assembler function for the complete observer task. In this revised
% implementation the demonstrator starts the task after a random delay
% (that servers the observer to go and harvest reward and be ready again in
% time) by poking in the center port. This will trigger a sound that
% indicates that the observer can now fixate on the observer deck. Once the
% observer pokes the stimulus is triggered and the demonstrator performs
% the task as trained. After the outcome is revealed (reward, wrong choice 
% punishment sound or early withdrawal punishment sound) the observer can
% leave and will be given a reward if it correctly fixated for the entire
% duration of the observation.

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
% LO, 4/1/2021, 1/12/2022
%-------------------------------------------------------------------------
global BpodSystem

%% Valve time and LED assignment
%If the correct side is provided as an input argument assign the valves to
%their functions (e.g. reward, wrong choice).
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
    leftPortAction = 'DemonReward';
    rightPortAction = 'DemonWrongChoice';
end

obsRewardValve = 2^3; %Port 4
obsRewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.obsRewardVolume, 4); %second value is Bpod index for the valve


%--------------------------------------------------------------------------
%% Generate the variable trial timers etc.

%Set up these delays even if they are unused here
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

% The delay between demonstrator poking and stimulus playing
preStimDelay = 0; %The demonstrator preStimDelay is replaced in the observer
% task by the time to the observer needs to initiate.

%Check the wait time for the demonstrator and add a random independent
%delay.
if isequal(BpodSystem.ProtocolSettings.minWaitTime,'exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'Exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'exponential')
    postStimDelay = generate_random_delay(1/0.1, 0.01, 1); %set lambda such that the mean is 0.1 : mean = 1/lambda
    waitTime = 1 + postStimDelay; %Add the delay to the 1 s of stimulus
else 
    waitTime = BpodSystem.ProtocolSettings.minWaitTime; %This is to be consisten with previous versions.
    postStimDelay = 0;
end

%Define a brief delay between the outcome for the demonstrator and
%revealing the fixation success to the observer.
outcomeSeparation = 0.1;
%This delay will only be used if the demonstrator is punished for wring
%choice or early withdrawal. Introducing outcomeSeparation will make Bpod
%idle in the respective states for the specified amount of time. In case
%the demonstrator is rewarded the state already lasts several tens of
%miliseconds and when the demonstrator does not choose there is no outcome
%signal that could be learned.

% Creat the struct to hold the task delays
taskDelays = struct();
taskDelays.trialStartDelay = trialStartDelay;
taskDelays.preStimDelay = preStimDelay;
taskDelays.waitTime = waitTime;
taskDelays.postStimDelay = postStimDelay;
taskDelays.interTrialInterval = interTrialInterval;
taskDelays.outcomeSeparation = outcomeSeparation;

%--------------------------------------------------------------------------
%% Assemble the state matrix


sma = NewStateMatrix(); %generate a new empty state matrix

sma = AddState(sma, 'Name', 'TrialStart', ...
    'Timer', interTrialInterval, ...
    'StateChangeCondition', {'Tup','DemonWaitForCenterFixation'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});
%Start the trial with a delay to allow the observer to finish drinking and
%to get in position for the upcoming trial. Have all the LEDs switched on
%to indicate that no action is currently possible.

sma = AddState(sma, 'Name', 'DemonWaitForCenterFixation', ...
    'Timer', 0, ...
    'StateChangeCondition', {'Port2In','DemonInitFixation'},...
    'OutputActions',{'PWM1',255,'PWM3',255,'PWM4',255});
%Remain in this state until the demonstrator initiates the trial by poking
%into the center port.

sma = AddState(sma, 'Name', 'DemonInitFixation',...
    'Timer',BpodSystem.ProtocolSettings.obsInitiationWindow, ...
    'StateChangeConditions', {'Tup','ObsDidNotInitiate','ObserverDeck1_1','ObsInitFixation','Port2Out','DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode', 2, 'PWM1', 255, 'PWM3', 255, 'PWM4', 255});
%This state is the demonstrator waiting for the observer to initiate. First,
%play a sound to indicate possibility to fixate to the observer (SoftCode2). The
%observer has the time obsInitationWindow to break the beam on the observer
%deck otherwise no initiation will be registered. If the observer does it
%successuflly the state machine moves on to PlayStimulus. As outputs the initiation tone
%is played to inform the observer that fixation is now possible, the two side LEDs
%and the observer LED are kept on and teensy gets the signal to count
%the observer deck beam breaks. If the demonstrator retracts during this
%period an eraly withdrawal is recorded.

sma = AddState(sma, 'Name', 'ObsInitFixation',...
    'Timer',0,...
    'StateChangeConditions', {'Tup','PlayStimulus', 'Port2Out','DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM4', 255,'ObserverDeck1',30});
%State that registers the fixation of the observer. To indicate successful
%fixation the side LEDs in the demonstrator side are switched off. Bpod
%sends byte 30 to teensy to start counting how often the observer deck beam
%is unbroken. If the demonstrator breaks fixation here, immediately advance
%to DemonEarlyWithdrawal.

sma = AddState(sma, 'Name', 'ObsDidNotInitiate',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','PlayStimulus','Port2Out','DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM1', 255, 'PWM3', 255, 'PWM4', 255,'ObserverDeck1',33});
%Register that the observer did not initiate in the correct time window to
%evaluate observer fixation success later. Bit 33 to teensy signals
%non-initiation and will be treated like unsucessful fixation without
%punishment. Switch off the side LEDs to indicate that stimulus
%presentation starts.

sma = AddState(sma, 'Name', 'PlayStimulus',...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup','DemonCenterFixationPeriod', 'Port2Out', 'DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode',1,'PWM4',255});
%Trigger the stimulus delivery to the demonstrator )SoftCode 1 and move on.
%The stimulus will keep playing until finished or until the SoftCode 255 is
%sent.
%If the demonstrator gets out of the port in that very moment register an
%early withdrawal.

sma = AddState(sma, 'Name', 'DemonCenterFixationPeriod',...
    'Timer',waitTime, ...
    'StateChangeConditions', {'Tup','DemonGoCue','Port2Out','DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM4',255});
%Period of demonstrator fixation. If successfull move on to go
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
%Reaction time until the demonstrator gets out of the center port. 

sma = AddState(sma, 'Name', 'DemonWaitForResponse',...
    'Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Port1In',leftPortAction,'Port3In',rightPortAction,'Tup','DemonDidNotChoose'},...
    'OutputActions', {'PWM4',255});
%This is the period to report the choice by poking into one of the side
%pokes. 

sma = AddState(sma,'Name', 'DemonReward',...
    'Timer',rewardValveTime, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'ValveState', RewardValve,'PWM2',255, incorrectPortLED, 255,'PWM4',255,'ObserverDeck1',31});
%Reward delivery to the demonstrator. First, switch off the stimulus if it
%is still playing (when extraStimTime is big) and then switch the LEDs of
%the incorrect port and the center on, so that the observer understands
%that the observation phase is completed. Keep the LED at the observer
%reward port still on. Finally, send bit 31 to teensy to stop counting the
%beam unbreakings.

sma = AddState(sma, 'Name', 'DemonWrongChoice',...
    'Timer',outcomeSeparation, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'SoftCode', 5, 'ObserverDeck1', 31});
%Wrong choice of the demonstrator leads to all LEDs being swithed on again
%after terminating the stim signal. The punishment noise is played and
%teensy gets again the bit 31 to tell it to stop counting unbroken beam
%events on the observer deck.
 
sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal',...
    'Timer',outcomeSeparation, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'SoftCode', 4, 'ObserverDeck1', 31}); 
%Finally, the same for an early withdrawal.

sma = AddState(sma, 'Name', 'DemonDidNotChoose',...
    'Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'ObserverDeck1', 31});
%In case the demonstrator does not choose a port in the time it gets all
%the LEDs are switched on again we continue to checking if the observer
%maintained in fixation.

sma = AddState(sma, 'Name', 'ObsCheckFixationSuccess',...
    'Timer',0, ...
    'StateChangeConditions', {'ObserverDeck1_3','ObsWaitForRewardRetrieval','ObserverDeck1_4','ObsEarlyWithdrawal','ObserverDeck1_5','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'ObserverDeck1',32});
%This is now the state where the observer's fixation success is going to be
%evaluated. Teensy recieves bit 32 telling it to report whether the mouse
%correctly fixated throughout the whole period. If yes event
%ObserverDeck1_3 will be reported if no ObserverDeck1_4 will be sent. If 
%the mouse did not initiate in the first place ObserverDeck1_5 will be
%registered. Note that at this point all the port LEDs are on.

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
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode',6});
%If the observer has broken fixation early it will be punished with a
%noise and an extra time out.

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