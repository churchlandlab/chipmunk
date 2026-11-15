function signal = extendStimulusTrain(signal, extraDuration, samplingFreq)
% Repeat actual samples, since the generated train can differ from nominal duration.
validateattributes(signal, {'numeric'}, {'2d', 'nonempty', 'finite'});
validateattributes(extraDuration, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
validateattributes(samplingFreq, {'numeric'}, {'scalar', 'finite', 'positive'});
nExtra = round(extraDuration * samplingFreq);
if nExtra > 0
    extra = repmat(signal, 1, ceil(nExtra / size(signal, 2)));
    signal = [signal extra(:, 1:nExtra)];
end
end
