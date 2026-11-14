function check_passive_visual_stim(outputFolder)
% PassiveVisualStim runs with anti-bias on; its trials have no choices.
data = runEmulatorSession(outputFolder,'PassiveVisualStim',struct('antiBiasStrength',1,'passiveReplayEnable',0), ...
    @(varargin) [], 'trialLimit', 6, 'timeout', 120);
assert(numel(data.RawEvents.Trial) == 6, 'Expected 6 trials, got %d.', numel(data.RawEvents.Trial));
disp('PASS: PassiveVisualStim session with anti-bias on');
end
