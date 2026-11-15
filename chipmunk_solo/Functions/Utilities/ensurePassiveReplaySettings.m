function ensurePassiveReplaySettings()
global BpodSystem
defaults = struct('passiveReplayEnable', 0, 'passiveReplayFraction', 1, ...
    'passiveReplayNTrials', [], 'passiveReplayOrder', 'sequential');
names = fieldnames(defaults);
for k = 1:numel(names)
    if ~isfield(BpodSystem.ProtocolSettings, names{k})
        BpodSystem.ProtocolSettings.(names{k}) = defaults.(names{k});
    end
end
end
