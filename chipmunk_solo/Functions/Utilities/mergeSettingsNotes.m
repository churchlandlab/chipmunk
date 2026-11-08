function mergeSettingsNotes()
% Fold protocol changelog into Data.Notes once, at save.
global BpodSystem
if ~isfield(BpodSystem.Data, 'Notes') || isempty(BpodSystem.Data.Notes)
    BpodSystem.Data.Notes = {};
end
if ~isfield(BpodSystem.Data, 'SettingsNotes')
    return
end
for k = 1:numel(BpodSystem.Data.SettingsNotes)
    text = BpodSystem.Data.SettingsNotes{k};
    if isempty(text)
        continue
    end
    if numel(BpodSystem.Data.Notes) < k || isempty(BpodSystem.Data.Notes{k})
        BpodSystem.Data.Notes{k} = text;
    elseif ~contains(char(string(BpodSystem.Data.Notes{k})), text)
        BpodSystem.Data.Notes{k} = [char(string(BpodSystem.Data.Notes{k})) ' | ' text];
    end
end
end
