function [sma, trialDelays, reviseChoiceFlag, pacedFlag] = PassiveVisualStimSMA(~)
% Play one visual stimulus and end the trial. No poke, reward, or punishment.
% The argument is ignored. Startup calls this with no arguments.
global BpodSystem

%--------------------------------------------------------------------------
%% Generate the variable trial timers etc.

interTrialInterval = generate_random_delay(BpodSystem.ProtocolSettings.interTrialDurLambda, BpodSystem.ProtocolSettings.interTrialDurMin, BpodSystem.ProtocolSettings.interTrialDurMax);
virtualObsInitDelay = generate_random_delay(BpodSystem.ProtocolSettings.virtualObsInitLambda, BpodSystem.ProtocolSettings.virtualObsInitMin, BpodSystem.ProtocolSettings.virtualObsInitMax);

preStimDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax);
%This delay may help reducing anticipatory signals to the
%stimulus (although in the poisson version the presentation of the first 
%stimulus is not predictable by definition)

%Check for the wait time
if isequal(BpodSystem.ProtocolSettings.minWaitTime,'exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'Exp') || isequal(BpodSystem.ProtocolSettings.minWaitTime,'exponential')
    postWaitDelay = generate_random_delay(1/0.1, 0.01, 0.5); %set lambda such that the mean is 0.1 : mean = 1/lambda
    waitTime = 0.5 + postWaitDelay; %Add the delay to the 1 s of stimulus
else
    waitTime = BpodSystem.ProtocolSettings.minWaitTime; %This is to be consisten with previous versions.
    postWaitDelay = 0;
end

%Create the struct to hold the task delays
trialDelays = struct();
trialDelays.preStimDelay = preStimDelay;
trialDelays.waitTime = waitTime;
trialDelays.postStimDelay = postWaitDelay;
trialDelays.interTrialInterval = interTrialInterval;
trialDelays.virtualObsInitDelay = virtualObsInitDelay;

%--------------------------------------------------------------------------
%% Assemble the state matrix

sma = NewStateMatrix(); %generate a new empty state matrix

sma = AddState(sma, 'Name', 'Sync', ...
    'Timer', 0.1, ...
    'StateChangeCondition', {'Tup','TrialStart'},...
    'OutputActions',{'BNC2', 1});

sma = AddState(sma, 'Name', 'TrialStart', ...
    'Timer', 0, ...
    'StateChangeCondition', {'Tup','PlayStimulus'},...
    'OutputActions',{});

sma = AddState(sma, 'Name', 'PlayStimulus',...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup', 'FinishTrial'},...
    'OutputActions', {'SoftCode',1});
%Trigger the stimulus delivery to the demonstrator )SoftCode 1 and move on.
%The stimulus will keep playing until finished or until the SoftCode 255 is
%sent.

sma = AddState(sma, 'Name', 'FinishTrial',...
    'Timer',0, ...
    'StateChangeConditions', {'Tup','>exit'},...
    'OutputActions', {});
%Finish the trial.


%--------------------------------------------------------------------------
%% Set whether the choice can be revised
reviseChoiceFlag = false;

%--------------------------------------------------------------------------
%% Set whether the demonstrator trials are paced
pacedFlag = false;
end