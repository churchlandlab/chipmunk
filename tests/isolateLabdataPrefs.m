function old = isolateLabdataPrefs(dataRoot)
% Point chipmunkDataRoot at a temporary labdata prefs file for tests.
old = getenv('LABDATA_PATH');
folder = fullfile(dataRoot, 'labdata');
mkdir(dataRoot);
mkdir(folder);
fid = fopen(fullfile(folder, 'user_preferences.json'), 'w');
assert(fid ~= -1, 'chipmunk_solo:TestPrefs', 'Could not write labdata prefs.');
fwrite(fid, jsonencode(struct('local_paths', {{dataRoot}})));
fclose(fid);
setenv('LABDATA_PATH', folder);
end
