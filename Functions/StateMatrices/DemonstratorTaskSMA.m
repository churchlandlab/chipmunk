function [sma, trialDelays, reviseChoiceFlag, pacedFlag] = DemonstratorTaskSMA(correctSideOnCurrent);
% [sma, trialDelays, reviseChoiceFlag, pacedFlag] = DemonstratorTaskSMA(correctSideOnCurrent);
%
% SMA assemly function for the DemonstratorTask. In this condition a
% demonstrator can self-initiate trials by poking into the center port after
% a set inter trial interval
% The choices will either be rewarded or punished with a sound and timeout.
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
%           -pacedFlag: Indicates whether the demonstrator trials are paced
%                      by an observer or virtually (pacedFlag = true) or
%                      whether it can self initiate (pacedFlag = false).
%
% LO, 4/1/2021, LO, 1/13/2022, 4/10/2022
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

virtualObsInitDelay = generate_random_delay(BpodSystem.ProtocolSettings.virtualObsInitLambda, BpodSystem.ProtocolSettings.virtualObsInitMin, BpodSystem.ProtocolSettings.virtualObsInitMax);
%The delay between demonstrator poking and virtual observer initiating.
%This is separtely assigned because the tone needs to be terminated before
%the trial can move on to the pre stimulus delay period. A pre/stimulus
%period is still necessary because the continuous tone for the simulated
%observer initation would allow the demonstrator to get a precise timing of
%the stimlus onset.

preStimDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax);
%This delay may help reducing anticipatory signals to the
%stimulus (although in the poisson version the presentation of the first 
%stimulus is not predictable by definition)

%Check for the wait time
if isequal(BpodSystem.ProtocolSettings.minWaitTime,'exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'Exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'exponential')
    postStimDelay = generate_random_delay(1/0.1, 0.01, 1); %set lambda such that the mean is 0.1 : mean = 1/lambda
    waitTime = 1 + postStimDelay; %Add the delay to the 1 s of stimulus
else
    waitTime = BpodSystem.ProtocolSettings.minWaitTime; %This is to be consisten with previous versions.
    postStimDelay = 0;
end

%Create the struct to hold the task delays
trialDelays = struct();
trialDelays.trialStartDelay = trialStartDelay;
trialDelays.preStimDelay = preStimDelay;
trialDelays.waitTime = waitTime;
trialDelays.postStimDelay = postStimDelay;
trialDelays.interTrialInterval = interTrialInterval;
trialDelays.virtualObsInitDelay = virtualObsInitDelay;

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
    'StateChangeCondition', {'Port2In','DemonInitFixation'},...
    'OutputActions',{'PWM1',255,'PWM3',255,'PWM4',255});
%Remain in this state until the demonstrator initiates the trial by poking
%into the center port.

sma = AddState(sma, 'Name', 'DemonInitFixation',...
    'Timer',virtualObsInitDelay, ...
    'StateChangeConditions', {'Tup','PreStimPeriod','Port2Out','DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode',2, 'PWM1', 255, 'PWM3', 255, 'PWM4', 255});
%This state is the demonstrator waiting for the virtual observer to
%initiate fixation at the observer deck before moving on to stimulus
%presentation.

sma = AddState(sma, 'Name', 'PreStimPeriod',...
    'Timer',preStimDelay, ...
    'StateChangeConditions', {'Tup','PlayStimulus','Port2Out','DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM4', 255});
%This state is the preStimulus delay where both animals are waiting for
%action!

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
    'StateChangeConditions', {'Tup','DemonWaitForWithdrawalFromCenter','Port2Out','DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode',3,'PWM4',255});
%After the required time to wait in the center is over a sound is played
%that tells the demonstrator that it can leave the poke now. If the
%demonstrator leaves the port at exactly the moment of the tone this means
%it is an early withdrawal.

sma = AddState(sma, 'Name', 'DemonWaitForWithdrawalFromCenter',...
    'Timer',0, ...
    'StateChangeConditions', {'Port2Out','DemonWaitForResponse'},...
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
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'SoftCode',255,'ValveState', RewardValve,'PWM2',255, incorrectPortLED, 255,'PWM4',255});
%Reward delivery to the demonstrator. First, switch off the stimulus if it
%is still playing (when extraStimTime is big) and then switch the LEDs of
%the incorrect port and the center on, so that the observer understands
%that the observation phase is completed. Keep the LED at the observer
%reward port still on.

sma = AddState(sma, 'Name', 'DemonWrongChoice',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWrongChoicePunishment'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'SoftCode',255});
%Wrong choice of the demonstrator leads to stop of the stimulus and
%switching on of all the LEDs. Move on to the punishment right away.

sma = AddState(sma, 'Name', 'DemonWrongChoicePunishment',...
    'Timer',BpodSystem.ProtocolSettings.wrongPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'SoftCode', 5});
%Wrong choice punishment of the demonstrator leads to all LEDs being swithed on again
%after terminating the stim signal. The punishment noise is played and a
%timeout is given to the demonstrator.
 
sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawalPunishment'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255}); 
%In the case of an early withdrawal by the demonstrator we first need to
%terminate the stimulus presentation with SoftCode 255 before delivering
%the punishment sound and timeout.

sma = AddState(sma, 'Name', 'DemonEarlyWithdrawalPunishment',...
    'Timer',BpodSystem.ProtocolSettings.earlyPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'SoftCode',4}); 
%Deliver the punisment noise with SoftCode 4 and give the demonstrator a
%timeout.

sma = AddState(sma, 'Name', 'DemonDidNotChoose',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});
%In case the demonstrator does not choose a port in the time it gets all
%the LEDs are switched on again we continue to checking if the observer
%maintained in fixation.

sma = AddState(sma, 'Name', 'FinishTrial',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','>exit'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});
%Finish the trial.

%--------------------------------------------------------------------------
%% Set whether the choice can be revised
reviseChoiceFlag = false;

%--------------------------------------------------------------------------
%% Set whether the demonstrator trials are paced
pacedFlag = false;
end