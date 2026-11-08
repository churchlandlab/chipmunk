function check_camera_registration()
% Run the task's camera registration against a Bpod-like object, not a struct.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path;cleanup=onCleanup(@() path(oldPath));
addpath(fullfile(root,'tests','fixtures','spikeglx'));
source=fileread(fullfile(root,'chipmunk_solo.m'));
block=regexp(source,'(?s)        if ephysOn\n(.*?)        else\n            labcamsCommand\(udplabcams,''softtrigger=1''','tokens','once');
assert(~isempty(block),'Camera registration block not found');
BpodSystem=TestBpod();
BpodSystem.PluginObjects=struct('SoundServer',struct('MasterOutput',7),'OtherPlugin',42);
udplabcams=TestCamera();
eval(block{1});
assert(isfield(BpodSystem.PluginObjects,'SoundServer'),'Camera startup erased the sound server');
assert(BpodSystem.PluginObjects.SoundServer.MasterOutput==7 && BpodSystem.PluginObjects.OtherPlugin==42);
assert(isequal(BpodSystem.PluginObjects.labcams,udplabcams));
fprintf('PASS: camera registration preserves sound and other Bpod plugins\n');
end
