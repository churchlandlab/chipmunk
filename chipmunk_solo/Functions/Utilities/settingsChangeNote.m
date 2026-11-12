function note = settingsChangeNote(oldSettings, newSettings)
% One line describing GUI fields that changed. Empty if nothing changed.
global BpodSystem
note = '';
if ~isfield(BpodSystem.GUIHandles, 'ParamEdit')
    names = fieldnames(newSettings);
else
    names = fieldnames(BpodSystem.GUIHandles.ParamEdit);
    if any(strcmp(names, 'manipLongCombo'))
        names = names(~strcmp(names, 'manipLongCombo'));
        names = [names; {'manipLongPulseMs'; 'manipLongGapMs'}];
    end
end
parts = {};
for k = 1:numel(names)
    name = names{k};
    if ~isfield(newSettings, name)
        continue
    end
    newValue = newSettings.(name);
    if ~isfield(oldSettings, name)
        parts{end+1} = sprintf('%s = %s', name, formatSetting(newValue)); %#ok<AGROW>
        continue
    end
    if ~isequaln(oldSettings.(name), newValue)
        parts{end+1} = sprintf('%s %s -> %s', name, formatSetting(oldSettings.(name)), formatSetting(newValue)); %#ok<AGROW>
    end
end
if ~isempty(parts)
    note = ['settings: ' strjoin(parts, '; ')];
end
end

function text = formatSetting(value)
if ischar(value) || isstring(value)
    text = char(value);
elseif isnumeric(value) || islogical(value)
    text = strtrim(sprintf('%g ', value));
else
    text = class(value);
end
end
