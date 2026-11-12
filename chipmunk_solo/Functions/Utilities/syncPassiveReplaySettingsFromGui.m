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
        h = BpodSystem.GUIHandles.ParamEdit.(name);
        value = get(h, 'String');
        if strcmp(get(h, 'Style'), 'popupmenu')
            value = value{get(h, 'Value')}; % Order is a dropdown
        else
            value = str2double(value);
        end
        BpodSystem.ProtocolSettings.(name) = value;
    end
end
end
