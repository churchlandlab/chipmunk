function check_ephys()
% SpikeGLX stays off unless a host is filled; connect failure is stored, not thrown.
root = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
global BpodSystem
oldBpod = BpodSystem;
cleanup = onCleanup(@() restore(oldPath,oldBpod));
addpath(genpath(fullfile(root,'Functions')));
addpath(fullfile(root,'vendor','SpikeGLX-MATLAB-SDK','API'));
prefs = fullfile(root,'spikeglx_prefs.mat');
prefsCleanup = onCleanup(@() deleteIfPresent(prefs));

assert(~ephysRecordingEnabled(struct()));
assert(~ephysRecordingEnabled(struct('spikeGLXHost','')));
assert(~ephysRecordingEnabled(struct('spikeGLXHost','  ')));
assert(ephysRecordingEnabled(struct('spikeGLXHost','jupiter.local')));

state = spikeglx_client('init','GRB001_20261101_120000');
assert(strcmp(state.runName,'GRB001_20261101_120000'));
spikeglx_client('set','host','127.0.0.1');
got = spikeglx_client('get');
assert(strcmp(got.host,'127.0.0.1'));
state = spikeglx_client('connect');
assert(~state.connected && ~isempty(state.lastError));
spikeglx_client('shutdown');

BpodSystem = struct('PluginObjects',struct());
labcams_ephys('start');
labcams_ephys('stop');
disp('PASS: ephys stays off when host is blank; connect failure is nonfatal');
end

function restore(oldPath,oldBpod)
global BpodSystem
path(oldPath);
BpodSystem = oldBpod;
end

function deleteIfPresent(pathName)
if exist(pathName,'file') == 2
    delete(pathName);
end
end
