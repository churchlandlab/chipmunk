function check_legacy_launchers()
% Exercise delegation without opening devices or changing stored settings.
root=fileparts(fileparts(mfilename('fullpath')));
global BpodSystem ChipmunkLauncherCall
oldBpod=BpodSystem;oldPath=path;oldFolder=pwd;
folder=tempname;mkdir(folder);mkdir(fullfile(folder,'chipmunk_solo'));
cleanup=onCleanup(@() restore(oldBpod,oldPath,oldFolder,folder));
cd(folder);clear chipmunk_solo
fid=fopen(fullfile(folder,'chipmunk_solo','chipmunk_solo.m'),'w');
fprintf(fid,'function chipmunk_solo(varargin)\nglobal BpodSystem ChipmunkLauncherCall\nChipmunkLauncherCall=struct(''args'',{varargin},''settings'',BpodSystem.ProtocolSettings);\nend\n');fclose(fid);
for name={'half_second_chipmunk_solo','half_second_chipmunk_ephys'}
 addpath(fullfile(root,'compat',name{1}));
 settings=struct('baseWait',.5,'minWaitTime',.2);
 BpodSystem=struct('Path',struct('ProtocolFolder',folder),'ProtocolSettings',settings);
 feval(name{1},3);
 assert(isequal(ChipmunkLauncherCall.args,{3}));
 assert(ChipmunkLauncherCall.settings.baseWait==.5 && ChipmunkLauncherCall.settings.minWaitTime==.2);
 if strcmp(name{1},'half_second_chipmunk_ephys')
  assert(strcmp(ChipmunkLauncherCall.settings.spikeGLXHost,'jupiter.local'));
  BpodSystem.ProtocolSettings.spikeGLXHost='custom-host';feval(name{1});
  assert(strcmp(ChipmunkLauncherCall.settings.spikeGLXHost,'custom-host'));
 else
  assert(~isfield(ChipmunkLauncherCall.settings,'spikeGLXHost'));
 end
end
clear chipmunk_solo
fprintf('PASS: legacy launchers delegate arguments, preserve settings and opt ephys into Jupiter\n');
end
function restore(oldBpod,oldPath,oldFolder,folder)
global BpodSystem ChipmunkLauncherCall
BpodSystem=oldBpod;ChipmunkLauncherCall=[];path(oldPath);clear chipmunk_solo
cd(oldFolder);rmdir(folder,'s');
end
