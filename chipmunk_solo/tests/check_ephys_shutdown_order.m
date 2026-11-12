function check_ephys_shutdown_order()
% closeChipmunkSession with the camera, sound and ephys endpoints replaced by fixtures/shutdown.
root=fileparts(fileparts(mfilename('fullpath')));
folder=tempname;mkdir(folder);oldPath=path;
global BpodSystem ChipmunkShutdownTest
oldBpod=BpodSystem;oldTest=ChipmunkShutdownTest;
cleanup=onCleanup(@() restore(folder,oldPath,oldBpod,oldTest));
addpath(fullfile(root,'Functions'));
addpath(fullfile(root,'tests','fixtures','shutdown'),'-begin');
for failure={'none','save','sound'}
    BpodSystem=struct('ProtocolSettings',struct('demonID','FakeSubject'), ...
        'Data',struct('nTrials',3,'Notes',{{'test note'}}),'GUIHandles',struct());
    target=fullfile(folder,[failure{1} '.mat']);
    if strcmp(failure{1},'save'),target=fullfile(folder,'missing','session.mat');end
    BpodSystem.Path.CurrentDataFile={target};
    ChipmunkShutdownTest=struct('failure',failure{1},'events',{{}},'recording',true);
    threw=false;
    try,closeChipmunkSession(true,[]);catch,threw=true;end
    assert(isequal(ChipmunkShutdownTest.events,{'camera','sound','ephys'}));
    assert(~ChipmunkShutdownTest.recording,'Ephys was left acquiring');
    if strcmp(failure{1},'none')
        assert(~threw);saved=load(target);
        assert(saved.SessionData.nTrials==3 && isfield(saved.SessionData,'EphysShutdownError'));
    elseif strcmp(failure{1},'save')
        assert(threw,'Save failure was swallowed');
    end
end
fprintf('PASS: behavioral save precedes camera/sound shutdown; ephys stops last, including save/sound failures\n');
end
function restore(folder,oldPath,oldBpod,oldTest)
global BpodSystem ChipmunkShutdownTest
path(oldPath);BpodSystem=oldBpod;ChipmunkShutdownTest=oldTest;rmdir(folder,'s');
end
