function appendTrialNote(trialIdx, text)
% Protocol changelog. Lives in Data.SettingsNotes so BpodNotebook cannot wipe it.
global BpodSystem
if nargin < 2 || isempty(text)
    return
end
validateattributes(trialIdx, {'numeric'}, {'scalar', 'integer', '>=', 1});
if isempty(BpodSystem.Data)
    BpodSystem.Data = struct();
end
if ~isfield(BpodSystem.Data, 'SettingsNotes') || isempty(BpodSystem.Data.SettingsNotes)
    BpodSystem.Data.SettingsNotes = {};
end
if numel(BpodSystem.Data.SettingsNotes) < trialIdx
    BpodSystem.Data.SettingsNotes{trialIdx} = '';
end
if isempty(BpodSystem.Data.SettingsNotes{trialIdx})
    BpodSystem.Data.SettingsNotes{trialIdx} = text;
else
    BpodSystem.Data.SettingsNotes{trialIdx} = [BpodSystem.Data.SettingsNotes{trialIdx} ' | ' text];
end
end
