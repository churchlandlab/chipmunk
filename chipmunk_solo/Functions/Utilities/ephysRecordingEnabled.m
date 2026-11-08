function on = ephysRecordingEnabled(settings)
% Opt-in SpikeGLX path: a nonempty host.
if nargin < 1 || ~isstruct(settings) || ~isfield(settings, 'spikeGLXHost')
    on = false;
    return
end
on = ~isempty(strtrim(settings.spikeGLXHost));
end
