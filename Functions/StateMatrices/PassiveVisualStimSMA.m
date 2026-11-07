function [sma, trialDelays, reviseChoiceFlag, pacedFlag] = PassiveVisualStimSMA(~, stimulusDuration)
% Present a complete passive train, with no port requirements or reward.
% The first argument retains the common assembler interface (trial side).
global BpodSystem
if nargin < 2
    stimulusDuration = 1 + BpodSystem.ProtocolSettings.extraStimDur;
end
validateattributes(stimulusDuration, {'numeric'}, {'scalar','finite','positive'});
interTrialInterval = generate_random_delay(BpodSystem.ProtocolSettings.interTrialDurLambda, ...
    BpodSystem.ProtocolSettings.interTrialDurMin, BpodSystem.ProtocolSettings.interTrialDurMax);
preStimDelay = generate_random_delay(BpodSystem.ProtocolSettings.preStimDelayLambda, ...
    BpodSystem.ProtocolSettings.preStimDelayMin, BpodSystem.ProtocolSettings.preStimDelayMax);
if any(strcmpi(string(BpodSystem.ProtocolSettings.minWaitTime), ["exp", "exponential"]))
    baseWait = BpodSystem.ProtocolSettings.baseWait;
    postWaitDelay = generate_random_delay(10, 0.01, baseWait);
    waitTime = baseWait + postWaitDelay;
else
    waitTime = BpodSystem.ProtocolSettings.minWaitTime;
    postWaitDelay = 0;
end
% Preserve legacy metadata fields; passive trials have no center-hold states.
trialDelays = struct('preStimDelay',preStimDelay,'waitTime',waitTime, ...
    'postStimDelay',postWaitDelay,'interTrialInterval',interTrialInterval, ...
    'virtualObsInitDelay',0);
sma = NewStateMatrix();
sma = AddState(sma, 'Name','Sync', 'Timer',0.1, ...
    'StateChangeConditions',{'Tup','TrialStart'}, 'OutputActions',{'BNC2',1});
sma = AddState(sma, 'Name','TrialStart', 'Timer',interTrialInterval, ...
    'StateChangeConditions',{'Tup','PlayStimulus'}, 'OutputActions',{});
sma = AddState(sma, 'Name','PlayStimulus', 'Timer',stimulusDuration, ...
    'StateChangeConditions',{'Tup','FinishTrial'}, 'OutputActions',{'SoftCode',1});
sma = AddState(sma, 'Name','FinishTrial', 'Timer',0, ...
    'StateChangeConditions',{'Tup','>exit'}, 'OutputActions',{'SoftCode',255});
reviseChoiceFlag = false;
pacedFlag = false;
end
