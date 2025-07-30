function [sma, trialDelays, reviseChoiceFlag, pacedFlag] = PassiveVisualStim(correctSideOnCurrent)
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
    postWaitDelay = generate_random_delay(1/0.1, 0.01, 0.5); %set lambda such that the mean is 0.1 : mean = 1/lambda
    waitTime = 0.5 + postWaitDelay; %Add the delay to the 1 s of stimulus
else
    waitTime = BpodSystem.ProtocolSettings.minWaitTime; %This is to be consisten with previous versions.
    postWaitDelay = 0;
end

%Create the struct to hold the task delays
trialDelays = struct();
trialDelays.trialStartDelay = trialStartDelay;
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