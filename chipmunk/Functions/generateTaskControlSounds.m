function generateTaskControlSounds(cueLoudness, earlyPunishLoudness, earlyPunishTimeout, wrongPunishLoudness, wrongPunishTimeout, soundCalibrationModelParams, trialDelays, obsEarlyPunishLoudness, obsEarlyPunishTimeout)
%generateTaskControlSounds(cueLoudness, earlyPunishLoudness, earlyPunishTimeout, wrongPunishLoudness, wrongPunishTimeout, soundCalibrationModelParams, trialDelays, obsEarlyPunishLoudness, obsEarlyPunishTimeout)
%generateTaskControlSounds(cueLoudness, earlyPunishLoudness, earlyPunishTimeout, wrongPunishLoudness, wrongPunishTimeout, soundCalibrationModelParams, trialDelays)
%
%Generates the sounds that signal different stages of the task. These are:
%A continuous tone that signals that initiation is possible for the
%observer, a short beep that indicates the end of demonstrator fixation
%after the stimulus period, a white noise for early withdrawals of the
%demonstrator, a brown noise for early withdrawals of the observer and a
%high pitched tone as a punshment for wrong choices of the demonstrator.
%
%-INPUTS: cueLoudness: The loudness for the observer initiation tone as 
%                      well as for the go cue.
%         earlyPunishLoudness: Arbitrary loudness value for early
%                              punishment sound.
%         earlyPunishTimeout: The timeouot period through which the
%                            respective sound will be played.
%         wrongPunishLoudness: As above for wrong choice punishments.
%         wrongPunishTimeout: As above for wrong choice punishments.
%         soundCalibrationModelParams: Coefficients for the fitted
%                                      polynomial relation between loudness
%                                      values and sound pressure.
%         trialDelays: Struct containing the delays assigned by the
%                      sma-assembler, used to determine the length of the
%                      observer initiation tone.
%         obsEarlyPunishLoudness (optional): Loudness of the pink noise
%                                            stimulus.
%         obsEarlyPunishTimeout (optional): Timeout period for early
%                                           withdawals from observer mice
%                                           in ObservationTraining (not in
%                                           the ObserverTask).
%
%
% Adapted from generateAndUploadSound in the auxiliary functions of
% Mudskipper2, 1/19/2021, 10/13/2021, 10/4/2022, LO
%--------------------------------------------------------------------------
global BpodSystem
samplingFreq = 192000; %Match the sampling frequency the sound card was initialized with, hard-coded!

startTrialCueFreq = 2000; %Set the frequency of the tiral initiation sound
goCueFreq = 7000; % Set the frequency of the goCue at the end of the demonstrator fixation
punishSoundFreq = 15000; %Set the frequency for wrong choice punishments

% The cue indicating the observer to start poking. In the current
% implementation the tone is played until the observer pokes or until the
% end of the window, resulting in the stimulus train being played. In case
% there is no observer take the maximum of the pre-stim delay.
if isfield(BpodSystem.ProtocolSettings, 'obsInitiationWindow')
    %When the main subject is the observer the tone can maximally last for
    %as long as the observer has the chance to initiate.
    startTrialCueWaveform = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* (cueLoudness*0.85) + soundCalibrationModelParams(2))) * GenerateSineWave(samplingFreq, startTrialCueFreq, BpodSystem.ProtocolSettings.obsInitiationWindow);% Sampling freq (hz), Sine frequency (hz), duration (s)
else
    %When the main subject is not the observer the initiation delay for a
    %virtual observer will be drawn randomly and stored in the trialDelays
    %struct. This delay will be used for the tone duration.
    startTrialCueWaveform = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* (cueLoudness*0.85) + soundCalibrationModelParams(2))) * GenerateSineWave(samplingFreq, startTrialCueFreq, trialDelays.virtualObsInitDelay);  %Use maximum pre-stimulus delay
end
startTrialCueSound = [zeros(1,size(startTrialCueWaveform,2)); startTrialCueWaveform];

% Go cue at the end of demonstrator fixation
goCueWaveform = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* cueLoudness + soundCalibrationModelParams(2))) * GenerateSineWave(samplingFreq, goCueFreq, 0.1);
goCueSound = [zeros(1,size(goCueWaveform,2)); goCueWaveform];

% Punishment for incorrect choice
wrongPunishWaveform = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* wrongPunishLoudness + soundCalibrationModelParams(2))) * GenerateSineWave(samplingFreq, punishSoundFreq, wrongPunishTimeout);
wrongPunishSound = [zeros(1,size(wrongPunishWaveform,2)); wrongPunishWaveform];

% Punishment for early withdrawals
earlyPunishAmplitude = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* earlyPunishLoudness + soundCalibrationModelParams(2)));%calculate amplitude
earlyPunishSound = [zeros(1,earlyPunishTimeout*samplingFreq); 2*earlyPunishAmplitude * rand(1, earlyPunishTimeout * samplingFreq)- earlyPunishAmplitude];

% Punishment for early withdrawals for the observer (pink noise signal,
% requires audio toolbox) if needed
if ~isempty(obsEarlyPunishLoudness)
obsEarlyPunishAmplitude = earlyPunishAmplitude * 0.5; % The 0.5*scalingFactor equalizes the power of the pink noise
%relatively well to the one of the white noise.
% obsEarlyPunishSound = [zeros(1,obsEarlyPunishTimeout * samplingFreq); (pinknoise(obsEarlyPunishTimeout * samplingFreq)'/0.1) * obsEarlyPunishAmplitude];
%Dividing the signal by 0.1 standardizes it (see the amplitude
%distribution: https://www.mathworks.com/help/audio/ref/pinknoise.html and

%Inserted to make more distinguishable from white noise
cn = dsp.ColoredNoise('brown','SamplesPerFrame',obsEarlyPunishTimeout*samplingFreq);
obsEarlyPunishSound = [zeros(1,obsEarlyPunishTimeout * samplingFreq); (cn()'/100) * obsEarlyPunishAmplitude];
end

% Upload sounds to sound server. Channel 1 reserved for stimuli
PsychToolboxSoundServer('Load', 2, startTrialCueSound);
PsychToolboxSoundServer('Load', 3, goCueSound);
PsychToolboxSoundServer('Load', 4, earlyPunishSound);
PsychToolboxSoundServer('Load', 5, wrongPunishSound);

if ~isempty(obsEarlyPunishLoudness) %only if there is an observer
PsychToolboxSoundServer('Load', 6, obsEarlyPunishSound);
end

end