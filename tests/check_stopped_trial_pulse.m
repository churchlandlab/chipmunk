function check_stopped_trial_pulse()
% Stop during an active trial records where its unsaved Sync pulse sits.
root=fileparts(fileparts(mfilename('fullpath')));
source=fileread(fullfile(root,'chipmunk_solo.m'));
block=regexp(source,'(?s)\n(        if ~isempty\(fieldnames\(RawEvents\)\)\n.*?\n        end)\n','tokens','once');
assert(~isempty(block),'Trial data block not found');
global BpodSystem
saved=BpodSystem;cleanup=onCleanup(@() restore(saved));

% Stopped mid-trial: no events, Bpod not in use -> marker after the saved trials.
BpodSystem=struct('Status',struct('BeingUsed',0),'Data',struct());
[marker,retrieved]=runBlock(block{1},struct(),5);
assert(isequal(marker,4) && ~retrieved,'Stopped trial 5 should mark a pulse after 4 saved trials');

% Normal trial: events saved, no marker.
BpodSystem=struct('Status',struct('BeingUsed',1),'Data',struct());
[marker,retrieved]=runBlock(block{1},struct('States',1),5);
assert(isempty(marker) && retrieved);

% Empty trial while running: warning only, no marker.
BpodSystem=struct('Status',struct('BeingUsed',1),'Data',struct());
lastwarn('');w=warning('off','all');[marker,retrieved]=runBlock(block{1},struct(),5);warning(w);
assert(isempty(marker) && ~retrieved);
disp('PASS: a stopped trial records its unsaved Sync pulse position');
end

function [marker,retrieved]=runBlock(code,RawEvents,TrialsDone) %#ok<INUSD>
global BpodSystem
retrieved=false; %#ok<NASGU>
[TrialSidesList,trialDelays,reviseChoiceFlag,ModalityRecord,stimulusDuration,stimTrainDuration, ...
    categoryBoundary,interStimulusIntervalList,visualIsiList,auditoryIsiList,trialBrightness,minInterval]=deal([]); %#ok<ASGLU>
code=strrep(code,'retrieveTrialData(','retrieved=true;noop(');
eval(code);
marker=[];
if isfield(BpodSystem.Data,'StoppedTrialPulse'),marker=BpodSystem.Data.StoppedTrialPulse;end
end

function noop(varargin)
end

function restore(saved)
global BpodSystem
BpodSystem=saved;
end
