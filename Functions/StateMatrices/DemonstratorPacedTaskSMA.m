function [sma, taskDelays, reviseChoiceFlag, pacedFlag] = DemonstratorPacedTaskSMA(correctSideOnCurrent);
% [sma, taskDelays, reviseChoiceFlag, pacedFlag] = DemonstratorPacedTaskSMA(correctSideOnCurrent);
%
% SMA assembler function for a demonstrator running the task alone.
% The start of the trials is indicated to the demonstrator by an auditory cue and the 
% switching off of the port LEDs.
% Please note that the state "ObsInitFixation" is kept here for naming
% consistency despite the absence of an observer.
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
% LO, 7/2/2021
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

%Generate a random time delay between trials to account for the observer
%harvesting its own reward and initiate again
interTrialInterval = generate_random_delay(BpodSystem.ProtocolSettings.interTrialDurLambda, BpodSystem.ProtocolSettings.interTrialDurMin, BpodSystem.ProtocolSettings.interTrialDurMax);

%The delay when the observer pokes until the demonstrator task starts -
%drawn from the same distribution as the pre-stimulus delay
trialStartDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax);

%The delay between demonstrator poking and stimulus playing
preStimDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax);

%Check for the wait time
if isequal(BpodSystem.ProtocolSettings.minWaitTime,'exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'Exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'exponential')
postStimDelay = generate_random_delay(1/0.1, 0.01, 1); %set lambda such that the mean is 0.1 : mean = 1/lambda
waitTime = 1 + postStimDelay; %Add the delay to the 1 s of stimulus
else 
  waitTime = BpodSystem.ProtocolSettings.minWaitTime; %This is to be consisten with previous versions.
  postStimDelay = 0;
end

% Creat the struct to hold the task delays
taskDelays = struct();
taskDelays.trialStartDelay = trialStartDelay;
taskDelays.preStimDelay = preStimDelay;
taskDelays.waitTime = waitTime;
taskDelays.postStimDelay = postStimDelay;
taskDelays.interTrialInterval = interTrialInterval;
%--------------------------------------------------------------------------
%% Assemble the state matrix

sma = NewStateMatrix(); %generate a new empty state matrix

sma = AddState(sma, 'Name', 'ObsTrialStart', ...
    'Timer', interTrialInterval, ...
    'StateChangeCondition', {'Tup','ObsInitFixation'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});

sma = AddState(sma, 'Name', 'ObsInitFixation', ...
    'Timer', trialStartDelay, ...
    'StateChangeCondition', {'Tup','DemonTrialStart'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonTrialStart','Timer',BpodSystem.ProtocolSettings.initiationWindow, ...
    'StateChangeConditions', {'Tup','DemonDidNotInitiate', 'Port2In', 'DemonInitFixation'},...
    'OutputActions', {'SoftCode', 2,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonInitFixation','Timer', preStimDelay, ...
    'StateChangeConditions', {'Tup','PlayStimulus', 'Port2Out', 'DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM4',255});

sma = AddState(sma, 'Name', 'PlayStimulus','Timer', 0, ...
    'StateChangeConditions', {'Tup','DemonCenterFixationPeriod', 'Port2Out', 'DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode',1,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonCenterFixationPeriod','Timer',waitTime, ...
    'StateChangeConditions', {'Tup','DemonGoCue', 'Port2Out', 'DemonEarlyWithdrawal'},...
    'OutputActions', {'PWM4',255});

sma = AddState(sma, 'Name', 'DemonGoCue','Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWaitForWithdrawalFromCenter'},...
    'OutputActions', {'SoftCode',3,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonWaitForWithdrawalFromCenter','Timer',0, ...
    'StateChangeConditions', {'Port2Out','DemonWaitForResponse'},...
    'OutputActions', {'PWM4',255});

sma = AddState(sma, 'Name', 'DemonWaitForResponse','Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
        'StateChangeConditions', {'Port1In', leftPortAction ,'Port3In',rightPortAction,'Tup','DemonDidNotChoose'},...
        'OutputActions', {'PWM4',255});

sma = AddState(sma,'Name', 'DemonReward','Timer',rewardValveTime, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'SoftCode',255,'ValveState', RewardValve,'PWM2',255,incorrectPortLED,255,'PWM4',255}); % Switch on the lights on the center and the incorrect port.
 
sma = AddState(sma,'Name', 'DemonWrongChoice','Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWrongChoiceTimeout'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255}); % Switch on the lights 

sma = AddState(sma, 'Name', 'DemonWrongChoiceTimeout','Timer',BpodSystem.ProtocolSettings.wrongPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode', 5}); 

sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal','Timer',0, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawalTimeout'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255}); 

sma = AddState(sma, 'Name', 'DemonEarlyWithdrawalTimeout','Timer',BpodSystem.ProtocolSettings.earlyPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode', 4}); 

sma = AddState(sma, 'Name', 'DemonDidNotChoose','Timer',0, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonDidNotInitiate','Timer',0, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});

sma = AddState(sma, 'Name', 'FinishTrial','Timer',0, ...
    'StateChangeConditions', {'Tup','>exit'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255, 'PWM4',255 });


%--------------------------------------------------------------------------
%% Set whether the choice can be revised
reviseChoiceFlag = false;

%% Set whether the demonstrator trials are paced
pacedFlag = true;

end