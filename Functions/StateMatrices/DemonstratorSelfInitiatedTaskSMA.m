function [sma, taskDelays, reviseChoiceFlag, pacedFlag] = DemonstratorSelfInitiatedTaskSMA(correctSideOnCurrent);
% [sma, taskDelays, reviseChoiceFlag, pacedFlag] = DemonstratorSelfInitiatedTaskSMA(correctSideOnCurrent);
%
% SMA assembler function for the rate task self-initiated by the demonstrator.
% In this condition it can initiate trials by poking into the center port and
% the choices will either be rewarded or punished with a sound and timeout.
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
% LO, 4/1/2021
%-------------------------------------------------------------------------
global BpodSystem

%% Valve time and LED assignment
%If the correct side is provided as an input argument assign the valves to
%their functions (e.g. reward, wrong choice).
if exist('correctSideOnCurrent') && ~isempty(correctSideOnCurrent) %input check
    rewardedSide = correctSideOnCurrent;
    if rewardedSide == 0 %the case for left side correct
        LeftPortAction = 'DemonReward';
        RewardValve = 2^0; %left-hand port represents port#0, therefore valve value is 2^0
        rewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.leftRewardVolume, 1); %second value is Bpod index for the valve
        RightPortAction = 'DemonWrongChoice';
        
    elseif rewardedSide == 1 %the case for right side correct
        RightPortAction = 'DemonReward';
        RewardValve = 2^2; %left-hand port represents port#0, therefore valve value is 2^0
        rewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.rightRewardVolume, 3);
        LeftPortAction = 'DemonWrongChoice';
        
    end

else %The dummy case assuming left
    LeftPortAction = 'DemonReward';
    RightPortAction = 'DemonWrongChoice';
    RewardValve = 2^0;
    rewardValveTime = 0;
end


%--------------------------------------------------------------------------
%% Generate the variable trial timers etc.

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
%--------------------------------------------------------------------------
%% Assemble the state matrix

sma = NewStateMatrix(); %generate a new empty state matrix

sma = AddState(sma, 'Name', 'DemonTrialStart', 'Timer', 0,...
    'StateChangeConditions', {'Port2In', 'DemonInitFixation'},...
    'OutputActions', {});

sma = AddState(sma, 'Name', 'DemonInitFixation','Timer', preStimDelay, ...
    'StateChangeConditions', {'Tup','PlayStimulus', 'Port2Out', 'DemonEarlyWithdrawal'},...
    'OutputActions', {});

sma = AddState(sma, 'Name', 'PlayStimulus','Timer', 0, ...
    'StateChangeConditions', {'Tup','DemonCenterFixationPeriod', 'Port2Out', 'DemonEarlyWithdrawal'},...
    'OutputActions', {'SoftCode',1});

sma = AddState(sma, 'Name', 'DemonCenterFixationPeriod','Timer',waitTime, ...
    'StateChangeConditions', {'Tup','DemonGoCue', 'Port2Out', 'DemonEarlyWithdrawal'},...
    'OutputActions', {});

sma = AddState(sma, 'Name', 'DemonGoCue','Timer',0, ...
    'StateChangeConditions', {'Tup','DemonWaitForResponse'},...
    'OutputActions', {'SoftCode',3});

sma = AddState(sma, 'Name', 'DemonWaitForResponse','Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Port1In', LeftPortAction, 'Port3In', RightPortAction,'Tup','DemonDidNotChoose'},...
    'OutputActions', {});

sma = AddState(sma, 'Name', 'DemonReward','Timer',rewardValveTime, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'ValveState', RewardValve}); 

sma = AddState(sma, 'Name', 'DemonWrongChoice','Timer',BpodSystem.ProtocolSettings.wrongPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'SoftCode', 5});

sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal','Timer',0, ...
    'StateChangeConditions', {'Tup','DemonEarlyWithdrawalPunishment'},...
    'OutputActions', {'SoftCode', 255});

sma = AddState(sma, 'Name', 'DemonEarlyWithdrawalPunishment','Timer',BpodSystem.ProtocolSettings.earlyPunishTimeout, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'SoftCode', 4}); 

sma = AddState(sma, 'Name', 'DemonDidNotChoose','Timer',0, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {}); %Here no sound indicating that no choice has been made

sma = AddState(sma, 'Name', 'FinishTrial','Timer',0, ...
    'StateChangeConditions', {'Tup','>exit'},...
    'OutputActions', {});

%--------------------------------------------------------------------------
%% Set whether the choice can be revised
reviseChoiceFlag = false;

%% Set whether the demonstrator trials are paced
pacedFlag = false;

end