function check_ephys_shutdown_order()
% Execute the runner's actual nested cleanup with isolated stream endpoints.
root=fileparts(fileparts(mfilename('fullpath')));
source=fileread(fullfile(root,'chipmunk_solo.m'));
first=strfind(source,'    function shutdownChipmunk()');
last=strfind(source,'function [visualIsiList, auditoryIsiList]');
body=strtrim(source(first:last-1));
body=body(1:end-3); % Drop the outer protocol's end, retaining its nested functions.
folder=tempname;mkdir(folder);oldPath=path;
global BpodSystem ChipmunkShutdownTest
oldBpod=BpodSystem;oldTest=ChipmunkShutdownTest;
cleanup=onCleanup(@() restore(folder,oldPath,oldBpod,oldTest));
fid=fopen(fullfile(folder,'shutdownHarness.m'),'w');
fprintf(fid,'function shutdownHarness()\nglobal BpodSystem ChipmunkShutdownTest\nephysOn=true;udplabcams=[];sessionClosed=false;\nshutdownChipmunk();\ntry,shutdownChipmunk();catch,end\n%s\n%s\nend\n',body,fileread(fullfile(root,'tests','fixtures','shutdown','endpoints.txt')));
fclose(fid);addpath(folder);
for failure={'none','save','sound'}
    BpodSystem=struct('ProtocolSettings',struct('demonID','FakeSubject'), ...
        'Data',struct('nTrials',3,'Notes',{{'test note'}}),'GUIHandles',struct());
    target=fullfile(folder,[failure{1} '.mat']);
    if strcmp(failure{1},'save'),target=fullfile(folder,'missing','session.mat');end
    BpodSystem.Path.CurrentDataFile={target};
    ChipmunkShutdownTest=struct('failure',failure{1},'events',{{}},'recording',true);
    threw=false;
    try,shutdownHarness();catch,threw=true;end
    assert(isequal(ChipmunkShutdownTest.events,{'camera','sound','ephys'}));
    assert(~ChipmunkShutdownTest.recording,'Ephys was left acquiring');
    if strcmp(failure{1},'none')
        assert(~threw);saved=load(target);
        assert(saved.SessionData.nTrials==3 && isfield(saved.SessionData,'EphysShutdownError'));
    elseif strcmp(failure{1},'save')
        assert(threw,'Save failure was swallowed');
    end
end
fprintf('PASS: behavioral save precedes camera/sound shutdown; ephys stops last, including save/sound failures; shutdown runs once\n');
end
function restore(folder,oldPath,oldBpod,oldTest)
global BpodSystem ChipmunkShutdownTest
clear shutdownHarness
path(oldPath);BpodSystem=oldBpod;ChipmunkShutdownTest=oldTest;rmdir(folder,'s');
end
