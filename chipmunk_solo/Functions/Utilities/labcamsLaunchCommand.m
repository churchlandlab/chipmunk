function command = labcamsLaunchCommand(configPath)
% Quote a selected config as one positional argument to Mercury's labcams CLI.
command = 'export LD_LIBRARY_PATH=""; export QT_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/qt5/plugins/platforms/; gnome-terminal -- labcams -w';
if isempty(configPath)
    return
end
assert(isfile(configPath), 'chipmunk_solo:CameraConfig', ...
    'Camera configuration file does not exist: %s', configPath);
config = jsondecode(fileread(configPath));
assert(isstruct(config) && isfield(config,'cams') && ~isempty(config.cams), ...
    'chipmunk_solo:CameraConfig', 'Camera configuration must contain a nonempty cams list.');
quote = char(39);
escaped = strrep(configPath, quote, [quote '"' quote '"' quote]);
command = [command ' ' quote escaped quote];
end
