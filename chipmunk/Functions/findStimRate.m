function stimulusRate = findStimRate(correctSideOnCurrentTrial, modalityOnCurrentTrial);
% stimulusRate = findStimRate(correctSideOnCurrentTrial, modalityOnCurrentTrial);
%
% Function to determine the rate of the stimulus to be presented based on
% the modality and the correct side assigned for the upcoming trial.
%
% INPUTS: -correctSideOnCurrentTrial: The correct side for the upcoming
%                                     trial, left = 0, right = 1.
%         -modalityOnCurrentTrial: The modality of the upcoming trial,
%                                  visual = 1, auditory = 2, multi-sensory
%                                  = 3.
%
% OUTPUT: -stimulusRate: The drawn stimulus rate.
%
% Note: The high-rate side and the modality specific frequencies are
% accessed directly from BpodSyste.ProtocolSettings.
%
% LO, 5/4/2021
%
%-------------------------------
global BpodSystem

%Determine the category boundary for possion and non-possion stim
if BpodSystem.ProtocolSettings.isPoissonStim == 0
    categoryBoundary = 12.5;    %events/s
else
    categoryBoundary = 12;
end

%Find elegible rates for the assigned side and modality
if (strcmpi(BpodSystem.ProtocolSettings.highRateSide ,'R') && correctSideOnCurrentTrial == 1) || (strcmpi(BpodSystem.ProtocolSettings.highRateSide ,'L') && correctSideOnCurrentTrial == 0)
    %Check which side is the high rate one and evaluate whether that one was picked for the current trial
    candidateAudFreq = BpodSystem.ProtocolSettings.audEventRateList(BpodSystem.ProtocolSettings.audEventRateList >= categoryBoundary);
    candidateVisFreq = BpodSystem.ProtocolSettings.visEventRateList(BpodSystem.ProtocolSettings.visEventRateList >= categoryBoundary);
    candidateMultFreq = BpodSystem.ProtocolSettings.multEventRateList(BpodSystem.ProtocolSettings.multEventRateList >= categoryBoundary);
else
    candidateAudFreq = BpodSystem.ProtocolSettings.audEventRateList(BpodSystem.ProtocolSettings.audEventRateList <= categoryBoundary);
    candidateVisFreq = BpodSystem.ProtocolSettings.visEventRateList(BpodSystem.ProtocolSettings.visEventRateList <= categoryBoundary);
    candidateMultFreq = BpodSystem.ProtocolSettings.multEventRateList(BpodSystem.ProtocolSettings.multEventRateList <= categoryBoundary);
end

%Choose from the candidate stim frequencies for the respective modality
%of the current trial
if modalityOnCurrentTrial == 1 %visual
    stimulusRate = candidateVisFreq(randperm(length(candidateVisFreq),1));
    %randomly draw one frequency from the list of candidates
elseif modalityOnCurrentTrial == 2 % only audio
    stimulusRate = candidateAudFreq(randperm(length(candidateAudFreq),1));
elseif modalityOnCurrentTrial == 3 % multi-sensory
    stimulusRate = candidateMultFreq(randperm(length(candidateMultFreq),1));
end
end
