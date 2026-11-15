function visualStimSignal = createVisualStimSignal(interStimulusIntervalList, SamplingFreq, stimBrightness, stimulusDuration);
% visualStimSignal = createVisualStimSignal(interStimulusIntervalList, SamplingFreq, stimBrightness, stimulusDuration);
% 
% Assemble the visual signal from the inter-stimulus interval list.
%
% INPUTS:-interStimulusIntervalList: Intervals between the individual
%                                    stimuli inside the stim train. The
%                                    train always starts with an interval
%                                    (could also be 0!) and ends with one.
%         -SamplingFreq: The specified sampling rate of the sound card
%         -stimBrightness: The bightness of the stimuli defined by how fast
%                          the LEDs will flicker within one stimulus
%                          leading to more or less light emitted per
%                          stimulus.
%         -stimulusDuration: The duration of each individual flash
%
% OUTPUT: -visualStimSignal: The ready-to-play visual signal for the
%                              given stim train     
%
% LO, 4/19/2021
%--------------------------------------------------------------------------

timevec = (1/SamplingFreq : 1/SamplingFreq : stimulusDuration); %No zero time stamps please!!!
flickerFreq = 200*stimBrightness; % we can't detect a 300 Hz flicker
sine_wave = sin(2*pi * flickerFreq * timevec); %Generate high frequency sine wave for the duration of the stimulus

[pks,locs] = findpeaks(sine_wave); %Find the high points...

flash = zeros(size(sine_wave));
flash(locs) = 1; %...and only use these ones to switch on the LED. The more times the LED is switched on during the stimulus the brighter

visualStimSignal = [];
for i = 1:length(interStimulusIntervalList)-1
    visualStimSignal = [visualStimSignal zeros(1, round(interStimulusIntervalList(i)*SamplingFreq)) flash];
end
 visualStimSignal = [visualStimSignal zeros(1, round(interStimulusIntervalList(end)*SamplingFreq))]; %The last interval is between the last stimulus and the end of the train
 
end