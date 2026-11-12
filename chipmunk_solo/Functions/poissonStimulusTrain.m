function interStimulusIntervalList = poissonStimulusTrain(stimTrainDuration, stimulusDuration, minInterval, stimulusRate);
% interStimulusIntervalList = poissonStimulusTrain(stimTrainDuration, stimulusDuration, minInterval, stimulusRate);
% 
% Generate a poisson stimulus train by discretizing the stimulus duration
% into a set of bins, whose duration is the sum of the tone/flash duration
% and the minimum interval between each stimulus, and then randomly
% assigning tone-interval pairs to the bins. Adapted from, Raposo et al.
% 2011 and Odoemene et al. 2018 and from a function written by Chaoqun Yin.
%
% INPUTS: -stimTrainDuration: Duration of the train of stimuli in s
%         -stimulusDuration: Duration of the sesnory stimulus tone / flash in s
%         -minInterval: The minimum interval between two stimuli
%         -stimulusRate: The average stimulus rate for the stim train.
%
% OUTPUT: -interStimulusIntervalList: -Vector containing the
%                                       inter-stimulus-intervals
%                                       constituting the stimulus train.
%                                       in seconds.
%
% LO, 4/19/2021
%---------------------------------------------------------------------------
validateattributes(stimTrainDuration, {'numeric'}, {'scalar','finite','positive'});
validateattributes(stimulusDuration, {'numeric'}, {'scalar','finite','positive'});
validateattributes(minInterval, {'numeric'}, {'scalar','finite','nonnegative'});
validateattributes(stimulusRate, {'numeric'}, {'scalar','finite','integer','nonnegative'});
nBins = stimTrainDuration / (stimulusDuration + minInterval);
assert(abs(nBins-round(nBins)) < 1e-9 && nBins >= 1, ...
    'chipmunk_solo:StimulusBins', 'Pulse plus gap must divide the stimulus train duration.');
if stimulusRate == 0
    interStimulusIntervalList = stimTrainDuration;
    return
end
bin_array = zeros(1, round(nBins));

if stimulusRate > length(bin_array)
    stimulusRate = length(bin_array);
    disp('The number of stimili you want is greater than the maximum! The maximum is used instead.');
end

bin_array(1 : stimulusRate) = 1; %Get the specified number of stimuli
shuffleIdx = randperm(length(bin_array)-1); %Get a set of randomly permuted indices, with one less entry than the bins
%This is to make sure the first bin alwas plays the stimulus
bin_array(2:end) = bin_array(shuffleIdx + 1); %There is the magic!

eventBin = find(bin_array == 1); %Find the bins that contain a stimulus event
interStimulusIntervalList = zeros(1, (length(eventBin)+1)); %There is one more interval than stimuli

for i = 1 : length(interStimulusIntervalList) %Assemble the intervals
    if i == 1
        interStimulusIntervalList(i) = (stimulusDuration + minInterval) * (eventBin(i) - 1);
    elseif i > 1 && i < length(interStimulusIntervalList)
        interStimulusIntervalList(i) = minInterval + (stimulusDuration + minInterval) * (eventBin(i) - eventBin(i-1) - 1);
    elseif i == length(interStimulusIntervalList)
        interStimulusIntervalList(i) = stimTrainDuration - (stimulusDuration + minInterval) * eventBin(i-1) + minInterval;
    end 
end

end