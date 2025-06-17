function pLeft = getAntiBiasPLeft(trialHistoryBiases, trialModalityBiases, upcomingModality, ...
    antiBiasStrength, prevChosenSide, prevOutcome)
% pLeft = getAntiBiasPLeft(trialHistoryBiases, trialModalityBiases, upcomingModality, ...
%    antiBiasStrength, prevCorrectSide, prevOutcome)
%
%Updates the probability for assigning the left side as to be the correct one
%for the upcoming trials. This is done based on the animal's modality- and
%choice history biases and it is weighted according to antiBiasStrength.
%
%-INPUTS: trialHistoryBiases: Biases for trial history. Rows are left and
%                             right choice made, columns outcomes. The
%                             sheets (or z-dimension) indicate the upcoming
%                             trial's correct side.
%         trialModalityBiases: The accumulated biases for the three
%                              different modality types: First column is
%                              visual, seond auditory, third multi-sensory.
%         antiBiasStrength: The weight assigned to the anti-bias procedure:
%                           One means complete reliance on the anti-bias
%                           procedure to determine the side for the
%                           upcoming choice, zero means ignore anti-biasing
%                           and rely only on propLeft.
%         prevChosenSide: The choice of the animal in the last trial. 0 =
%                         left, 1 = right.
%         prevOutcome: The outcome resulting from this choice.
%
%-OUTPUTS: pLeft: The proportion of the correct sides to be left for
%                 upcoming trials. 
%
%Commented and variable-checked from Mudskipper2 internal function, LO,
%1/25/2021
%--------------------------------------------------------------------------

% Find the context of the last completed trial and get scenario of right or
% left chocie
successPair = squeeze(trialHistoryBiases(prevChosenSide + 1, prevOutcome + 1, :));
succSum = sum(successPair);

% Based on the previous successes on this type of trial,
% preferentially choose the harder option
pLM = trialModalityBiases(upcomingModality);  % prob desired for left based on modality-specific bias
pLT = successPair(2) / succSum;  % same based on prev trial
iVar2M = 1 / (pLM - 1/2) ^ 2; % inverse variance for modality
iVar2T = 1 / (pLT - 1/2) ^ 2; % inverse variance for trial history

if succSum == 0 || iVar2T > 10000
    % Handle degenerate cases, trial history uninformative
    pLeft = pLM;
elseif iVar2M > 10000
    % Handle degenerate cases, modality bias uninformative
    pLeft = pLT;
else
    % The interesting case... combine optimally
    pLeft = pLM * (iVar2T / (iVar2M + iVar2T)) + pLT * iVar2M / (iVar2M + iVar2T);
end

% Weight pLeft from anti-bias by antiBiasStrength
pLeft = antiBiasStrength * pLeft + (1 - antiBiasStrength) * 0.5;

end
