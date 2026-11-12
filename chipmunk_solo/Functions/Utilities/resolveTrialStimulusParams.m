function trial = resolveTrialStimulusParams(stimulusRate)
% Per-trial brightness, pulse and gap. Never writes session defaults.
global BpodSystem
ensureStimulusManipulationSettings();
s = BpodSystem.ProtocolSettings;
validateattributes(stimulusRate, {'numeric'}, {'scalar', 'finite'});
validateattributes(s.stimBrightness, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
validateattributes(s.manipDimBrightness, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
validateattributes(s.manipFractionPercent, {'numeric'}, {'scalar', '>=', 0, '<=', 100});
validateattributes(s.manipNormalPulseMs, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(s.manipLongPulseMs, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(s.manipNormalGapMs, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
validateattributes(s.manipLongGapMs, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
preset = lower(strtrim(char(s.manipPreset)));
trial.brightness = s.stimBrightness;
trial.stimulusDuration = s.manipNormalPulseMs / 1000;
trial.minInterval = s.manipNormalGapMs / 1000;
trial.manipulated = false;
trial.kind = '';
if strcmp(preset, 'standard')
    return
end
if isfield(s, 'isPoissonStim') && ~s.isPoissonStim
    error('chipmunk_solo:ManipulationGenerator', ...
        'Stimulus manipulation presets require isPoissonStim = 1.');
end
if strcmp(preset, 'equalized')
    rates = equalizedSessionRates(s);
    if isempty(rates) || stimulusRate <= 0
        return
    end
    trial.manipulated = true;
    trial.kind = 'equalized';
    trial.brightness = s.stimBrightness * min(rates) / stimulusRate;
    return
end
validateattributes(s.manipEligibleRates, {'numeric'}, {'vector', 'finite', 'nonnegative'});
if ~ismember(stimulusRate, s.manipEligibleRates)
    return
end
if rand >= 1 - s.manipFractionPercent/100
    trial.manipulated = true;
    if strcmp(preset, 'dim')
        trial.kind = 'dim';
        trial.brightness = s.manipDimBrightness;
    elseif strcmp(preset, 'long')
        nBins = floor(1000 / (s.manipLongPulseMs + s.manipLongGapMs) + 1e-9);
        if stimulusRate > nBins
            trial.manipulated = false;
            return
        end
        trial.kind = 'long';
        trial.stimulusDuration = s.manipLongPulseMs / 1000;
        trial.minInterval = s.manipLongGapMs / 1000;
    else
        error('chipmunk_solo:UnknownManipPreset', 'Unknown manipPreset %s.', preset);
    end
end
end

function rates = equalizedSessionRates(s)
rates = [];
names = {'visEventRateList', 'audEventRateList', 'multEventRateList'};
for k = 1:numel(names)
    name = names{k};
    if isfield(s, name) && ~isempty(s.(name))
        rates = [rates, s.(name)(:)']; %#ok<AGROW>
    end
end
rates = rates(isfinite(rates) & rates > 0);
end
