function [sma, taskDelays, reviseChoiceFlag, pacedFlag] = ObserverTaskSMA(correctSideOnCurrent);
% [sma, taskDelays, reviseChoiceFlag, pacedFlag] = ObserverTaskSMA(correctSideOnCurrent);
%
% SMA assembler function for the complete observer task. The observer
% triggers trials for the demonstrator by breaking the observer deck beam.
% It then has to fixate and watch the entire demonstrator trial. If it
% stays in fixation sucessfully it can retrieve a reward on the back of its
% chamber. The observer reward does not mirror the one delivered to the
% demonstrator but is rather dependent on staying observing for the
% necessary amount of time. If the demonstrator does not complete the trial
% or does not initiate the observer will be able to also harvest rewards if
% it stays observing.

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
interTrialInterval = 0; %No extra time imposed between trials here.

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
    'Timer', 0, ...
    'StateChangeCondition', {'ObserverDeck1_1','ObsInitFixation'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255});
%ObserverDeck1_1 refers to the beam on the observer deck being broken

sma = AddState(sma, 'Name', 'ObsInitFixation', ...
    'Timer', trialStartDelay, ...
    'StateChangeCondition', {'Tup','DemonTrialStart'},...
    'OutputActions',{'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'ObserverDeck1',30});
%Sending the value 30 to Teensy will indicate the start of the counting of
%unbreakings of the observer.

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
    'StateChangeConditions', {'Tup','DemonWaitForResponse'},...
    'OutputActions', {'PWM4',255});

sma = AddState(sma, 'Name', 'DemonWaitForResponse','Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
        'StateChangeConditions', {'Port1In', leftPortAction ,'Port3In',rightPortAction,'Tup','DemonDidNotChoose'},...
        'OutputActions', {'PWM4',255});

sma = AddState(sma,'Name', 'DemonReward','Timer',rewardValveTime, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'ValveState', RewardValve,'PWM2',255,incorrectPortLED,255,'PWM4',255, 'ObserverDeck1', 31});
% Switch the lights on in the center and the incorrect port and leave the
% correct one off, send "Stop counting" (31) to Teensy

sma = AddState(sma, 'Name', 'DemonWrongChoice','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode', 5, 'ObserverDeck1', 31});
 
sma = AddState(sma, 'Name', 'DemonEarlyWithdrawal','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'SoftCode',255,'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode', 4, 'ObserverDeck1', 31}); 
% Play the punishment sound and send stop counting to teensy, switch on all
% the LEDs.

% sma = AddState(sma, 'Name', 'DemonEarlyWithdrawalTimeout','Timer',0, ...
%     'StateChangeConditions', {'Tup','FinishTrial'},...
%     'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255, 'SoftCode', 4});
% Currently there is no extra timeout for early withdrawals once the
% demonstrator is exposed to the demonstrator

sma = AddState(sma, 'Name', 'DemonDidNotChoose','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'ObserverDeck1',31});
% Send stop counting to Teensy and switch LEDs on.

sma = AddState(sma, 'Name', 'DemonDidNotInitiate','Timer',0, ...
    'StateChangeConditions', {'Tup','ObsCheckFixationSuccess'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'ObserverDeck1',31});

sma = AddState(sma, 'Name', 'ObsCheckFixationSuccess','Timer',0, ...
    'StateChangeConditions', {'ObserverDeck1_3','ObsWaitForRewardRetrieval','ObserverDeck1_4','ObsEarlyWithdrawal'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255,'PWM4',255,'ObserverDeck1',32});

sma = AddState(sma, 'Name', 'ObsWaitForRewardRetrieval','Timer',BpodSystem.ProtocolSettings.timeToChoose, ...
    'StateChangeConditions', {'Port4In','ObsReward', 'Tup','FinishTrial'},...
    'OutputActions', {'PWM1',255,'PWM2',255,'PWM3',255});
% Use the time to choose from the demonstrator here to define how long the
% observer may take to harvest its reward.

sma = AddState(sma, 'Name', 'ObsReward','Timer',obsRewardValveTime, ...
    'StateChangeConditions', {'Tup','FinishTrial'},...
    'OutputActions', {'ValveState', obsRewardValve,'PWM1',255,'PWM2',255,'PWM3',255});

sma = AddState(sma, 'Name', 'ObsEarlyWithdrawal','Timer',0, ...
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