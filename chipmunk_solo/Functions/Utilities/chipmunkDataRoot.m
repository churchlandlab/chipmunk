function root = chipmunkDataRoot()
% Session files go under labdata local_paths{1} (see user_preferences.json).
pref = labdataPreferencesFile();
if isfile(pref)
    data = jsondecode(fileread(pref));
    assert(isfield(data,'local_paths') && ~isempty(data.local_paths), ...
        'chipmunk_solo:DataRoot', 'labdata preferences have no local_paths: %s', pref);
    root = firstPath(data.local_paths);
    assert(~isempty(root), 'chipmunk_solo:DataRoot', 'labdata local_paths is empty in %s', pref);
    return
end
global BpodSystem
assert(~isempty(BpodSystem) && isfield(BpodSystem,'Path') && ...
    isfield(BpodSystem.Path,'DataFolder') && ~isempty(BpodSystem.Path.DataFolder), ...
    'chipmunk_solo:DataRoot', ...
    'Missing %s and no Bpod data folder.', pref);
root = BpodSystem.Path.DataFolder;
end

function pref = labdataPreferencesFile()
folder = getenv('LABDATA_PATH');
if isempty(folder)
    folder = fullfile(getenv('HOME'), 'labdata');
end
pref = fullfile(folder, 'user_preferences.json');
end

function root = firstPath(paths)
if iscell(paths)
    root = char(paths{1});
elseif isstring(paths)
    root = char(paths(1));
else
    root = char(paths);
end
root = strtrim(root);
end
