function [updatedTrialModalityBiases, updatedTrialHistoryBiases] = updateAntiBiasArrays(...
    trialModalityBiases, trialHistoryBiases, currentTrialModality, currentTrialChoice,...
    currentTrialOutcome, prevCorrectSide, prevChosenSide, prevOutcome, antiBiasTau);
% [updatedTrialModalityBiases, updatedTrialHistoryBiases] = updateAntiBiasArrays(...
%   trialModalityBiases, trialHistoryBiases, currentTrialModality, currentTrialChoice,...
%   currentTrialOutcome, prevCorrectSide, prevChosenSide, prevOutcome, antiBiasTau);
%
% Old description:
% Based on what happened on the last completed trial, update our beliefs
% about the animal's biases. modeRightArray tracks how likely he is to go
% right for each modality. successArray tracks how likely he is to succeed
% for left or right given what he did on the previous trial.
%
% Note: we'll actually use antiBiasTau * 3 for updating the
% modality-related side bias. If we don't, and there's only one modality,
% the updates will cause oscillation against a perfectly consistent
% strategy.
%
% For an exponential function, the pdf = (1/tau)*e^(-t/tau)
% The integral from 0 to 1 is [1 - e^(-1/tau)]
% This lets us do exponential decay using only the current
% outcome and previous biases
%- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
% Newly added description:
% Function to estimate modality-related and trial history biases.
% These biases are modeled as exponential decay functions with a
% half life of antiBiasTau. To update the accumulted biases
% from the previous trials are re-weighted and the choice and outcome in
% the just completed trial (currentTrial) are added.
%
%-INPUTS: trialModalityBiases: The accumulated biases for the three
%                              different modality types: First column is
%                              visual, second auditory, third multi-sensory.
%         trialHistoryBiases: Biases for trial history. Rows are left and
%                             right choice made, columns outcomes. The
%                             sheets (or z-dimension) indicate the side
%                             that would have been correct on the just
%                             completed trial (currentTrial).
%         currentTrialModality: Modlity of the trial just completed, 1 =
%                               visual, 2 = auditory, 3 = multi-sensory.
%         currentTrialChoice: Side choice of the animal for the just
%                             completed trial. 0 = left, 1 = right.
%         currentTrialOutcome: Outcome of the choice just made. 0 = Wrong
%                              choice, 1 = correct choice.
%         prevCorrectSide: The side that was correct in the trial preceding
%                          the just completed trial. 0 = left, 1 = right.
%         prevChosenSide: The side chosen by the animal in the trial
%                         preceding the just completed trial. 0 = left, 1 = right
%         prevOutcome: Outcome of the choice made by the animal in the
%                      trial preceding the just completed one. 0 = Worong
%                      choice, 1 = correct choice.
%         antiBiasTau: Half-life or rate parameter of the exponential decay
%                      function for modality or trial history biases.
%
%-OUTPUTS: updatedTrialModalityBiases: The updated version of
%                                      trialModalityBiases taking the just
%                                      completed trial into account.
%          updatedTrialHistoryBiases: see above.
%
% NOTE: L
% Adapted from internal function in Mudskipper2, variable renaming and
% commenting LO, 1/25/2021
%--------------------------------------------------------------------------

%Set the weights for modality bias and trial history bias, respectively
antiAlternationW = 1 - exp(-1/(3*antiBiasTau)); %3 because there are three modalities? LO
antiBiasW = 1 - exp(-1/antiBiasTau); %Are these are the integrals of the the bias distributions?

modality = currentTrialModality;
updatedTrialModalityBiases = trialModalityBiases;
if ~isnan(currentTrialChoice)
    updatedTrialModalityBiases(modality) = antiAlternationW * currentTrialChoice + (1 - antiAlternationW) * trialModalityBiases(modality);
%Estimate of the right-ward propensity of the animal for each sensory modality.
%Assumes an exponential decay of importance of the choice
%history on similar trials, that is, with the same modality.
end

% Can only update arrays if we already had a trial in the history (since we
% have a two-trial dependence)
updatedTrialHistoryBiases = trialHistoryBiases;
if ~isnan(prevChosenSide)
    updatedTrialHistoryBiases(prevChosenSide+1, prevOutcome+1, prevCorrectSide+1) = antiBiasW * (currentTrialOutcome > 0) + ...
        (1-antiBiasW) * trialHistoryBiases(prevChosenSide+1, prevOutcome+1, prevCorrectSide+1);
    %1-antiBiasW: is the rest of the trial history integral, while
    %antiBiasW represents the last choice.
    %Columns represent success at trial n-2, where n is the number of
    %behavioral loops, rows are L or right choices of the animal at trial
    %n-2 and "sheets" is the correct side a the most recently performed
    %trial. When one updates the array, only the value of the respective
    %index position, representing the similar choice conditions are
    %updated. For instance, if the trial n-2 has been a correct left choice
    %and the just performed trial (n-1) was left
    %then the matrix element (1,2,1) will be accessed.
end
end

