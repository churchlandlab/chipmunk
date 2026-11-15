function [sma, taskDelays, reviseChoiceFlag] = ObserverTaskSMA(correctSideOnCurrent);
% [sma, taskDelays, reviseChoiceFlag] = ObserverTaskSMA(correctSideOnCurrent);
%
% SMA assemly function for the ObserverTask condition. In this condition the
% observer mouse initiates a trial for the demonstrator by breaking the beam
% adjacent to the demonstrator chamber wall (read out as BNC1 low). After a
% brief variable delay an auditory go cue is played and the port LEDs for the
% demonstrator are switched off. The mouse has now a time window to start a
% trial by poking into the center port and
% proceed with the regular task. After the demonstrator has harvested the
% reward or received punishment the port LEDs are switched on again and it
% is evaluated whether the observer quit the beam break or not. If not
% it will be rewarded at its on port and a new trial can begin.
%
% INPUTS (optional): -correctSideOnCurrent: The side designated to be
%                                           rewarded during the current trial
%                                           if chosen.
%
% Outputs: - sma: The state machine to be sent to Bpod to run the trial.
%          - taskDelays: A struct containing the pre-stimulus delay and the
%                        wait time generated for the current trial.
%
% LO, 4/1/2021


%-----------------------------
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
        IncorrectPortLED = 'PWM3'; %To be able to selectively switch this one on
    elseif rewardedSide == 1 %the case for right side correct
        RightPortAction = 'DemonReward';
        RewardValve = 2^2; %left-hand port represents port#0, therefore valve value is 2^0
        rewardValveTime = GetValveTimes(BpodSystem.ProtocolSettings.rightRewardVolume, 3);
        
        LeftPortAction = 'DemonWrongChoice';
        IncorrectPortLED = 'PWM1'; %To be able to selectively switch this one on
    end
    
    ObsValve = 2^3;
    obsValveTime = GetValveTimes(BpodSystem.ProtocolSettings.obsRewardVolume, 4);
else %The dummy case assuming left
    LeftPortAction = 'DemonReward';
    RightPortAction = 'DemonWrongChoice';
    IncorrectPortLED = 'PWM3';
    RewardValve = 2^0;
    ObsRewardValve = 2^4;
    rewardValveTime = 0;
    obsValveTime = 0;
end


%--------------------------------------------------------------------------
%% Generate the variable trial timers etc.

%The delay when the observer pokes until the demonstrator task starts -
%drawn from the same distribution as the pre-stimulus delay
trialStartDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax);

%The delay between demonstrator poking and stimulus playing
preStimDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax);

%Check for the wait time
if isequal(BpodSystem.ProtocolSettings.minWaitTime,'exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'Exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'exponential');
postStimDelay = generate_random_delay(1/0.1, 0.01, 1); %set lambda such that the mean is 0.1 : mean = 1/lambda
waitTime = 1 + postStimDelay; %Add the delay to the 1 s of stimulus
else 
  waitTime = BpodSystem.ProtocolSettings.minWaitTime;
end

% Creat the struct to hold the task delays
taskDelays = struct();
taskDelays.preStimDelay = preStimDelay;
taskDelays.waitTime = waitTime;
%--------------------------------------------------------------------------
%% Assemble the state matrix

sma = NewStateMatrix(); %generate a new empty state matrix


% sma = SetGlobalTimer(sma, 'TimerID', 1, 'Duration', BpodSystem.ProtocolSettings.earlyPunishTimeout,...
%     'OnsetDelay', 0,'Channel','SoftCode',4);
% sma = SetGlobalTimer(sma, 'TimerID', 2, 'Duration', BpodSystem.ProtocolSettings.wrongPunishTimeout,...
%     'OnsetDelay', 0,'Channel','SoftCode',5);
% %Set the punishment noises to global timers, so that the state machine can
%move on and check on the observer while the demonstrator receives its
%punishment.

sma = SetGlobalCounter(sma, 1, 'BNC1High', 1);
%Use the global counter No1 and let it count all the BNC1Low events. If the
%count exceeds 1 then choose an alternative state change. Here, this would
%track when the beam is restored during the observer fixation period

sma = AddState(sma, 'Name', 'ObsInitFixation', ...
    'Timer', trialStartDelay, ...
    'StateChangeCondition', {'Tup','DemonTrialStart'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonTrialStart','Timer',BpodSystem.ProtocolSettings.initiationWindow, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess', 'Port2In', 'DemonInitFixation'},...
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
    'StateChangeConditions', {'Tup','DemonWaitForResponse'},...
    'OutputActions', {'SoftCode',3,'PWM4',255});

sma = AddState(sma, 'Name', 'DemonWaitForResponse','Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Port1In', LeftPortAction, 'Port3In', RightPortAction,'Tup','DemonDidNotChoose'},...
    'OutputActions', {'PWM4',255});

sma = AddState(sma, 'Name', 'DemonReward','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'ValveState', RewardValve,'PWM2',255,IncorrectPortLED,255,'PWM4',255}); % Switch on the lights on the center and the incorrect port.

sma = AddState(sma, 'Name', 'DemonWrongChoice','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'GlobalTimerTrig',2,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255}); %Global timer 2 is hard punish sound

sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'GlobalTimerTrig',1,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255}); %Global timer 1 is early withdrawal sound

sma = AddState(sma, 'Name', 'DemonDidNotChoose','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});

sma = AddState(sma, 'Name', 'ObsCheckFixationSuccess','Timer',0.01, ...
    'StateChangeConditions', {'GlobalCounter1_End','FinishTrial','Tup','ObsWaitForRewardRetrieval'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255}); %How to improve the LED switching

sma = AddState(sma, 'Name', 'ObsWaitForRewardRetrieval','Timer',0, ...
    'StateChangeConditions', {'Port4In','ObsReward'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255});

sma = AddState(sma, 'Name', 'ObsReward','Timer',0, ...
    'StateChangeConditions', {'Port4Out','FinishTrial'},...
    'OutputActions', {'ValveState', ObsRewardValve,'PWM1',255,'PWM2',255,'PWM3',255});

sma = AddState(sma, 'Name', 'FinishTrial','Timer',0, ...
    'StateChangeConditions', {'Tup','>exit'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255, 'PWM4',255 });

%--------------------------------------------------------------------------
%% Define whether demonstrator can revise choice

reviseChoiceFlag = false; 
end





