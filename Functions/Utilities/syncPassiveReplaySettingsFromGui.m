function syncPassiveReplaySettingsFromGui()
% Read edits at Stop even if Update was not clicked. Never evaluate GUI text.
global BpodSystem
ensurePassiveReplaySettings();
names = {'passiveReplayEnable', 'passiveReplayFraction', 'passiveReplayOrder'};
if ~isfield(BpodSystem.GUIHandles, 'ParamEdit')
    return
end
for k = 1:numel(names)
    name = names{k};
    if isfield(BpodSystem.GUIHandles.ParamEdit, name) && ...
            isgraphics(BpodSystem.GUIHandles.ParamEdit.(name))
        value = get(BpodSystem.GUIHandles.ParamEdit.(name), 'String');
        if ~strcmp(name, 'passiveReplayOrder')
            value = str2double(value);
        end
        BpodSystem.ProtocolSettings.(name) = value;
    end
end
end
