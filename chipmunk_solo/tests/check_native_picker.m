function check_native_picker(outputFolder)
% Run in fresh MATLAB with native_picker_input.py driving the real GUI externally.
global BpodSystem
assert(isempty(BpodSystem),'Run in a fresh MATLAB process before Bpod.');
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'tests'),genpath(fullfile(root,'Functions')));
mkdir(outputFolder);
selected=fullfile(outputFolder,'picked.json');
fid=fopen(selected,'w');fprintf(fid,'{"cams":[{"name":"picker-test"}]}');fclose(fid);
s=load(fullfile(root,'Experiments','VisualTask.mat'));
BpodSystem=struct('ProtocolSettings',s.ProtocolSettings,'Path',struct());
BpodSystem.Path.Settings=fullfile(outputFolder,'FakeSubject','chipmunk_solo','Session Settings','VisualTask.mat');
BpodSystem.Path.DataFolder=fullfile(outputFolder,'Data');
oldLab=isolateLabdataPrefs(BpodSystem.Path.DataFolder);
labCleanup=onCleanup(@() restoreLab(oldLab));
settings=initChipmunk;
assert(strcmp(settings.labcamsConfig,selected));
fprintf('PASS: native picker Open and Cancel retain the selected JSON\n');
end
function restoreLab(oldLab)
if isempty(oldLab)
    setenv('LABDATA_PATH','');
else
    setenv('LABDATA_PATH',oldLab);
end
end
