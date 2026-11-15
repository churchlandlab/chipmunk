function auditoryStimSignal = createAuditoryStimSignal(interStimulusIntervalList, SamplingFreq, stimulusDuration,...
    soundType, stimLoudness, addedNoiseLoudness, CalibrationModelParams);
% auditoryStimSignal = createAuditoryStimSignal(interStimulusIntervalList, SamplingFreq, stimulusDuration,...
%    soundType,stimLoudness, addedNoiseLoudness, CalibrationModelParams);
%
% Assemble the auditory signal from the inter-stimulus interval list.
%
% INPUTS: -interStimulusIntervalList: Intervals between the individual
%                                     stimuli inside the stim train. The
%                                     train always starts with an interval
%                                     (could also be 0!) and ends with one.
%         -SamplingFreq: The specified sampling rate of the sound card
%         -stimulusDuration: The duration of each individual tone
%         -soundType: Specifier of the stimulus sound as a string, options
%                     are: 'target' = constant 12 KHz pure tone,
%                     'target + envelope' = 12 KHz pure tone with
%                     crescendo - decrescendeo amplitude modulation over
%                     the duration of the tone and 'whiteNoise + envelope'
%                     = amplitude modulated white noise.
%         -stimLoudness: Peak loudness of the tone
%         -addedNoiseLoudness: The loudness of small-amplitude added noise
%         -CalibrationModelParams: Loudness calibration parameters
%
% OUTPUT: -auditoryStimSignal: The ready-to-play auditory signal for the
%                              given stim train
%
% LO, 4/19/2021
%--------------------------------------------------------------------------

targetFrequency = 12000; % Set the desired frequency for the auditory stimuli.
%This value got changed from 15 to 12 kHZ because the punishment sound is set as a
%15 kHz tone, LO

timevec = (1/SamplingFreq : 1/SamplingFreq : stimulusDuration); %Well, there is no time zero!

signal_amplitude = 10^(1/10*(CalibrationModelParams(1)*stimLoudness + CalibrationModelParams(2))); %Loudness of the stimuli
noise_amplitude = 10^(1/10*(CalibrationModelParams(1)*addedNoiseLoudness + CalibrationModelParams(2))); %Loudness of constant added noise
envelope = sin([pi/(SamplingFreq*stimulusDuration):pi/(SamplingFreq*stimulusDuration):pi]); %Create an increasing-decreasing half wave to modulate the loudness across the tone duration

%Evaluate the desired type of stimulation sound
if strcmp(soundType, 'target + envelope')
    soundpart = signal_amplitude * (sin(2*pi * targetFrequency * timevec) .* envelope);
elseif strcmp(soundType, 'target')
    soundpart = signal_amplitude * (sin(2*pi * targetFrequency * timevec));
elseif strcmp(soundType, 'whiteNoise + envelope')
    wnoise = signal_amplitude * 2 * (rand(1,length(timevec))-0.5);
    soundpart = wnoise .* envelope;
end
    
%Start assembling the stimulus train
auditoryStimSignal = [];
for i = 1:length(interStimulusIntervalList)-1
    auditoryStimSignal = [auditoryStimSignal zeros(1,round(interStimulusIntervalList(i)*SamplingFreq)) soundpart];
end
auditoryStimSignal = [auditoryStimSignal zeros(1,round(interStimulusIntervalList(end)*SamplingFreq))]; %The last interval is the silence between last stimulus and end of the train

    
%Add a smaller amplitude white noise to the signal
auditoryStimSignal = auditoryStimSignal + noise_amplitude*2*(rand(size(auditoryStimSignal))-0.5);

end