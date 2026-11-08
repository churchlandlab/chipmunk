function check_prestart_cancel()
% Exercise the runner's post-uiwait guard before any trial preparation.
root=fileparts(fileparts(mfilename('fullpath')));
source=fileread(fullfile(root,'chipmunk_solo.m'));
block=regexp(source,'(?s)uiwait\(BpodSystem.GUIHandles.Figures.DemonFigure\);[^\n]*\n(.*?)\nelse\n','tokens','once');
assert(~isempty(block));
folder=tempname;mkdir(folder);oldPath=path;
cleanup=onCleanup(@() restore(folder,oldPath));
fid=fopen(fullfile(folder,'prestartHarness.m'),'w');
fprintf(fid,['function [entered,finished]=prestartHarness(active)\n' ...
    'BpodSystem.Status.BeingUsed=active;entered=false;finished=false;\n%s\n' ...
    'entered=true;\nfunction finishSession(),finished=true;end\nend\n'],block{1});
fclose(fid);addpath(folder);
[entered,finished]=prestartHarness(false);assert(~entered && finished,'Stopped task entered trial preparation');
[entered,finished]=prestartHarness(true);assert(entered && ~finished,'Started task was cancelled');
fprintf('PASS: Stop before Start finalizes without entering the trial loop\n');
end
function restore(folder,oldPath)
clear prestartHarness
path(oldPath);rmdir(folder,'s');
end
