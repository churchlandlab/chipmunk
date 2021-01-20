function generateTaskControlSounds(cueLoudness, earlyPunishLoudness, earlyPunishTimeout, wrongPunishLoudness, wrongPunishTimeout, soundCalibrationModelParams)
%generateTaskControlSounds(cueLoudness, earlyPunishLoudness, earlyPunishTimeout, wrongPunishLoudness, wrongPunishTimeout, soundCalibrationModelParams)
%
%Generates the sounds that signal different stages of the task. These are:
%a cue to indicate that the observer is ready and that the demonstrator can
%initiate a trial, the go cue at the end of the demonstrator fixation, the
%punishment for wrong choices and the early withdrawal punishment noise.
%The frequencies and characteristics of these sounds are set at the
%beginning of the function here, instead of them being passed as input
%arguments.
%
%-INPUTS: cueLoudness: The loudness for the start trial cue as well as for
%                      the go cue.
%         earlyPunishLoudness: Arbitrary loudness value for early
%                              punishment sound.
%         earlyPunishTimout: The timeouot period through which the
%                            respective sound will be played.
%         wrongPunishLoudness: As above for wrong choice punishments.
%         wrongPunishTimeout: As above for wrong choice punishments.
%         soundCalibrationModelParams: Coefficients for the fitted
%                                      polynomial relation between loudness
%                                      values and sound pressure.
%
%Adapted from generateAndUploadSound in the auxiliary functions of
%Mudskipper2, 1/19/2021, LO
%--------------------------------------------------------------------------

samplingFreq = 192000; %Match the sampling frequency the sound card was initialized with, hard-coded!

startTrialCueFreq = 4000; %Set the frequency of the tiral initiation sound
goCueFreq = 7000; % Set the frequency of the goCue at the end of the demonstrator fixation
punishSoundFreq = 15000; %Set the frequency for wrong choice punishments

% The cue indicating the demonstrator to start the trial
startTrialCueWaveform = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* cueLoudness + soundCalibrationModelParams(2))) * GenerateSineWave(samplingFreq, startTrialCueFreq, 0.1);% Sampling freq (hz), Sine frequency (hz), duration (s)
startTrialCueSound = [zeros(1,size(startTrialCueWaveform,2)); startTrialCueWaveform];

% Go cue at the end of demonstrator fixation
goCueWaveform = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* cueLoudness + soundCalibrationModelParams(2))) * GenerateSineWave(samplingFreq, goCueFreq, 0.1);
goCueSound = [zeros(1,size(goCueWaveform,2)); goCueWaveform];

% Punishment for incorrect choice
wrongPunishWaveform = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* wrongPunishLoudness + soundCalibrationModelParams(2))) * GenerateSineWave(samplingFreq, 15000, wrongPunishTimeout);
wrongPunishSound = [zeros(1,size(wrongPunishWaveform,2)); wrongPunishWaveform];

% Punishment for early withdrawals
earlyPunishAmplitude = 0.15 * 10^(1/10*(soundCalibrationModelParams(1)* earlyPunishLoudness + soundCalibrationModelParams(2)));%calculate amplitude
earlyPunishSound = [zeros(1,earlyPunishTimeout*samplingFreq); 2*earlyPunishAmplitude * rand(1, earlyPunishTimeout * samplingFreq)- earlyPunishAmplitude];

% Upload sounds to sound server. Channel 1 reserved for stimuli
PsychToolboxSoundServer('Load', 2, startTrialCueSound);
PsychToolboxSoundServer('Load', 3, goCueSound);
PsychToolboxSoundServer('Load', 4, earlyPunishSound);
PsychToolboxSoundServer('Load', 5, wrongPunishSound);
end