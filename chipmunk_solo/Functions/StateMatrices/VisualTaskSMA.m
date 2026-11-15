function [sma, trialDelays, reviseChoiceFlag, pacedFlag] = VisualTaskSMA(correctSideOnCurrent)
% ponytail: same state machine as MultipleModalitiesTaskSMA, without port LEDs.
if nargin < 1
    correctSideOnCurrent = [];
end
[sma, trialDelays, reviseChoiceFlag, pacedFlag] = MultipleModalitiesTaskSMA(correctSideOnCurrent, false);
end
