function ensureStimulusManipulationSettings()
global BpodSystem
defaults = struct('manipPreset','standard', 'manipEligibleRates',[4 20], ...
    'manipFractionPercent',25, 'manipDimBrightness',30, ...
    'manipNormalPulseMs',15, 'manipLongPulseMs',75, ...
    'manipNormalGapMs',25, 'manipLongGapMs',125);
names = fieldnames(defaults);
for k = 1:numel(names)
    if ~isfield(BpodSystem.ProtocolSettings, names{k})
        BpodSystem.ProtocolSettings.(names{k}) = defaults.(names{k});
    end
end
end
