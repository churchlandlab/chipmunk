function [ok,message]=labcams_ephys(command)
% The cameras stop after the behavioral file and notes are on disk.
global BpodSystem ChipmunkShutdownTest
assert(strcmp(command,'stop') && ChipmunkShutdownTest.recording);
if ~strcmp(ChipmunkShutdownTest.failure,'save')
    checkpoint=load(BpodSystem.Path.CurrentDataFile{1});
    assert(checkpoint.SessionData.nTrials==3);
    assert(contains(fileread(fullfile(fileparts(BpodSystem.Path.CurrentDataFile{1}),'notes.txt')),'test note'));
end
ChipmunkShutdownTest.events{end+1}='camera';ok=true;message='';
end
