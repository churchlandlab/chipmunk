function interStimulusIntervalList = twoIntervalStimulusTrain(stimulusRate, shortInterval, longInterval, stimulusDuration, stimTrainDuration);
% interStimulusIntervalList = twoIntervalStimulusTrain(stimulusRate, shortInterval, longInterval, stimulusDuration, stimTrainDuration);
%
% Function to assemble a list of stimulus events. In this version of the
% rate task the rate is given by drawing combinations of short and long
% intervals between the individual stimuli. See Pisupati et al., 2021 for
% more information.
%
% INPUTS: -stimulusRate: The final rate of the stimulus train
%         -shortInterval: The short interval between stimuli in s
%         -longInterval: The long interval between stimuli in s
%         -stimulusDuration: Duration of the sesnory stimulus tone / flash in s
%         -stimTrainDuration: Duration of the train of stimuli in s
%
% OUTPUT: -interStimulusIntervalList: -Vector containing the
%                                       inter-stimulus-intervals
%                                       constituting the stimulus train.
%                                       1 = short interval, 2 = long interval
%         
% LO, 4/17/2021
%----------------------------------------

% Transform to milisecond for ease of calculation but retain as seconds in
% input for transfer to the signal generation
shortInterval = shortInterval*1000;
longInterval = longInterval*1000;
stimulusDuration = stimulusDuration*1000;
stimTrainDuration = stimTrainDuration*1000;

%Get the possible combination of short and long intervals to deliver the
%stimuli at the specified frequency

max_nr_shorti = floor((stimTrainDuration - stimulusDuration) / (shortInterval + stimulusDuration));
%Find the maximum number of short intervals and stimulus duration
%determining the highest frequency (16 Hz)
nr_shorti = [0 : max_nr_shorti]; %The possibilities

nr_longi  = floor(((stimTrainDuration - stimulusDuration) -  nr_shorti .* (shortInterval + stimulusDuration)) ./ (longInterval + stimulusDuration));
%Get the number of possible long intervals to fit in.

stim_strength = nr_shorti ./ (nr_shorti + nr_longi);
actual_duration = nr_longi * (longInterval + stimulusDuration) + nr_shorti * (shortInterval + stimulusDuration) + stimulusDuration;
%The expected stim duration for the respective combination

stim_matrix = [stim_strength', nr_shorti', nr_longi', actual_duration', nr_longi' + nr_shorti' + 1];
% take only stimuli that are longer than 930 ms
stim_matrix = stim_matrix(stim_matrix(:,4) > 930,:);

%--------------------------------------------------------------------------
%Choose the combination of intervals to represent the designated stimulus
%frequency

possible_stim = stim_matrix(stim_matrix(:,5) == stimulusRate,:); %Find mixture that satisfies the desired frequency

if isempty(possible_stim)
    [min_difference, ind] = min(abs(stim_matrix(:,5) - stimulusRate));
    this_stim = stim_matrix(ind,:);
    %Find the closest if no mix matched the frequency
else %Pick one if more than one mix exists
    ind = randperm(size(possible_stim,1));
    this_stim = possible_stim(ind(1),:);
end

% create the corresponding inter stimulus interval list in seconds
stim = [ones(1,this_stim(2))*shortInterval/1000 ones(1,this_stim(3))*longInterval/1000];
%this_stim(2) = shortInterval, this_stim(3) = longInterval
rand_indices = randperm(length(stim)); %Shuffle them up
interStimulusIntervalList = [0 stim(rand_indices) (stimTrainDuration-this_stim(4))/1000]; %Add a zero-duratation interval at the beginning.
%This is done so the inter-stimulus-interval list for the poisson train and
%the rate task are the same and visal / auditory signal can be constructed
%in the same way. Similarly, add the silence period at the end of the stim
%train.

end