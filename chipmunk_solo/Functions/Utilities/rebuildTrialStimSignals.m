function [signal, duration] = rebuildTrialStimSignals(trialIdx, samplingFreq)
% Reconstruct the intended train, not the exact exposure of an interrupted trial.
% Noise samples are regenerated. Missing saved settings are an error, not a fallback.
global BpodSystem
data = BpodSystem.Data;
settings = data.TrialSettings(trialIdx);
modality = data.Modality(trialIdx);
validateattributes(modality, {'numeric'}, {'scalar', 'integer', '>=', 1, '<=', 3});
flashDuration = data.StimulusDuration(trialIdx);
validateattributes(flashDuration, {'numeric'}, {'scalar', 'finite', 'positive'});
channels = cell(1, 2);
for channel = 1:2
    if modality ~= 3 && modality ~= channel
        continue
    end
    isi = data.InterStimulusIntervalList{trialIdx, channel};
    validateattributes(isi, {'numeric'}, {'vector', 'nonempty', 'finite', 'nonnegative'});
    if channel == 1
        validateattributes(settings.stimBrightness, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
        channels{1} = createVisualStimSignal(isi, samplingFreq, settings.stimBrightness, flashDuration);
    else
        validateattributes(settings.stimLoudness, {'numeric'}, {'scalar', 'finite'});
        validateattributes(settings.soundCalibrationModelParams, {'numeric'}, {'vector', 'numel', 2, 'finite'});
        channels{2} = createAuditoryStimSignal(isi, samplingFreq, flashDuration, ...
            'whiteNoise + envelope', settings.stimLoudness, 10, settings.soundCalibrationModelParams);
    end
end
signal = zeros(2, max(cellfun(@numel, channels)));
for channel = 1:2
    signal(channel, 1:numel(channels{channel})) = channels{channel};
end
signal = extendStimulusTrain(signal, data.ExtraStimDuration(trialIdx), samplingFreq);
duration = size(signal, 2) / samplingFreq;
end
