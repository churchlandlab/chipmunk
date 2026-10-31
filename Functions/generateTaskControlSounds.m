function generateTaskControlSounds(cueLoudness, earlyPunishLoudness, earlyPunishTimeout, wrongPunishLoudness, wrongPunishTimeout, soundCalibrationModelParams, trialDelays)
% Cue, go, early-withdrawal, and wrong-choice sounds for one trial.
% The trial-start cue lasts virtualObsInitDelay. Channel 1 is the stimulus.
samplingFreq = 192000;

startTrialCueFreq = 2000;
goCueFreq = 7000;
punishSoundFreq = 15000;

amplitude = @(loudness) 0.15 * 10^(1/10*(soundCalibrationModelParams(1)*loudness + soundCalibrationModelParams(2)));

startTrialCueWaveform = amplitude(cueLoudness*0.85) * GenerateSineWave(samplingFreq, startTrialCueFreq, trialDelays.virtualObsInitDelay);
startTrialCueSound = [zeros(1,size(startTrialCueWaveform,2)); startTrialCueWaveform];

goCueWaveform = amplitude(cueLoudness) * GenerateSineWave(samplingFreq, goCueFreq, 0.1);
goCueSound = [zeros(1,size(goCueWaveform,2)); goCueWaveform];

wrongPunishWaveform = amplitude(wrongPunishLoudness) * GenerateSineWave(samplingFreq, punishSoundFreq, wrongPunishTimeout);
wrongPunishSound = [zeros(1,size(wrongPunishWaveform,2)); wrongPunishWaveform];

earlyPunishAmplitude = amplitude(earlyPunishLoudness);
earlyPunishSound = [zeros(1,earlyPunishTimeout*samplingFreq); 2*earlyPunishAmplitude * rand(1, earlyPunishTimeout * samplingFreq) - earlyPunishAmplitude];

PsychToolboxSoundServer('Load', 2, startTrialCueSound);
PsychToolboxSoundServer('Load', 3, goCueSound);
PsychToolboxSoundServer('Load', 4, earlyPunishSound);
PsychToolboxSoundServer('Load', 5, wrongPunishSound);
end
