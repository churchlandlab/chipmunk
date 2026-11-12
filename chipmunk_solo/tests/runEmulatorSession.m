function [data,file] = runEmulatorSession(outputFolder, experiment, overrides, act, varargin)
% Run one FakeSubject chipmunk_solo session on an idle Bpod, driven by a timer.
%   overrides  settings changed from the experiment file and the short test timings below
%   act(state,nDone,held)  called every tick during a trial. held = [left center right] ports.
%                          It pokes with ManualOverride and sets ChipmunkSessionTest.stopped
%                          when it presses Stop.
% Options: 'trialLimit' (run to this many trials), 'timeout' (s), 'beforeStart' (function).
% Returns the saved SessionData and its file. The task window stays open for the caller.
global BpodSystem ChipmunkSessionTest
p = inputParser;
addParameter(p,'trialLimit',[]);
addParameter(p,'timeout',90);
addParameter(p,'beforeStart',[]);
parse(p,varargin{:});
o = p.Results;
root = fileparts(fileparts(mfilename('fullpath')));
oldPaths = BpodSystem.Path;
oldFolder = pwd;
oldLab = getenv('LABDATA_PATH');
cleanup = onCleanup(@() restore(oldPaths,oldFolder,oldLab));
addpath(root,fullfile(root,'tests'),genpath(fullfile(root,'Functions'))); % Stop removes the protocol folder.
[~,~] = mkdir(outputFolder);
cd(outputFolder); % Match rig launches where the protocol is not the current folder.
% Synthetic calibration is for test waveforms only; no production files are edited.
local = fullfile(outputFolder,'Bpod Local');
[~,~] = mkdir(fullfile(local,'Calibration Files'));
TargetSPLs = [40 50 60];
NoiseAmplitudes = [.001 .01 .1];
save(fullfile(local,'Calibration Files','WhiteNoiseCalibration.mat'),'TargetSPLs','NoiseAmplitudes');
BpodSystem.Path.LocalDir = local;
BpodSystem.Path.ProtocolFolder = fileparts(root);
BpodSystem.Path.DataFolder = fullfile(outputFolder,'Data');
isolateLabdataPrefs(BpodSystem.Path.DataFolder);

settings = load(fullfile(root,'Experiments',[experiment '.mat']));
s = settings.ProtocolSettings;
s.demonID = 'FakeSubject';
s.labcamsAddress = '';
s.spikeGLXHost = '';
s.propLeft = 1;
s.antiBiasStrength = 0;
s.minWaitTime = .1;
s.minWaitTimeStep = 0;
s.interTrialDurMin = .01;
s.interTrialDurMax = .02;
s.preStimDelayMin = .01;
s.preStimDelayMax = .02;
s.stimLoudness = 40;
s.goCueLoudness = 40;
s.wrongPunishLoudness = 40;
s.earlyPunishLoudness = 40;
s.extraStimDur = .05;
names = fieldnames(overrides);
for k = 1:numel(names)
    s.(names{k}) = overrides.(names{k});
end
BpodSystem.ProtocolSettings = s;
settingsFolder = fullfile(outputFolder,'FakeSubject','chipmunk_solo','Session Settings');
[~,~] = mkdir(settingsFolder);
BpodSystem.Path.Settings = fullfile(settingsFolder,[experiment '.mat']);
ProtocolSettings = s;
save(BpodSystem.Path.Settings,'ProtocolSettings');
BpodSystem.Data = struct();
BpodSystem.Status.BeingUsed = 1;
BpodSystem.Status.CurrentProtocolName = 'chipmunk_solo';
BpodSystem.Status.CurrentStateName = '';
BpodSystem.ProtocolStartTime = now*100000;

ChipmunkSessionTest.stopped = false;
ChipmunkSessionTest.error = '';
ChipmunkSessionTest.lastState = '';
ChipmunkSessionTest.started = tic;
assert(isempty(timerfindall('Tag','ChipmunkSessionDriver')),'Previous session driver leaked.');
period = .03;
if ~isempty(o.trialLimit) && o.trialLimit > 3, period = .005; end
driver = timer('Tag','ChipmunkSessionDriver','ExecutionMode','fixedSpacing','Period',period, ...
    'TimerFcn',@(t,~) drive(t,act,o));
ChipmunkSessionTest.driver = driver;
driverCleanup = onCleanup(@() delete(driver));
start(driver);
if isempty(o.trialLimit)
    chipmunk_solo;
else
    chipmunk_solo(o.trialLimit);
end
stop(driver);
assert(isempty(ChipmunkSessionTest.error),ChipmunkSessionTest.error);
file = BpodSystem.Path.CurrentDataFile{1};
saved = load(file);
data = saved.SessionData;
end

function drive(driver,act,o)
global BpodSystem ChipmunkSessionTest
% A deleted timer can still have a callback queued during the next GUI startup.
if ~isvalid(driver) || ~isstruct(ChipmunkSessionTest) || ...
        ~isfield(ChipmunkSessionTest,'driver') || ~isequal(driver,ChipmunkSessionTest.driver)
    return
end
try
    assert(toc(ChipmunkSessionTest.started) <= o.timeout,'Session test timed out.');
    init = findall(findall(0,'Tag','ChipmunkInit'),'Style','pushbutton','String','Initialize');
    if ~isempty(init)
        callback = get(init(1),'Callback');
        handles = callback{2};
        set(handles.demonID,'String','FakeSubject');
        set(handles.demonWeight,'String','25');
        set(handles.rigNo,'String','emulator');
        set(handles.researcher,'String','test');
        feval(callback{1},init(1),[],callback{2:end});
        return
    end
    if isfield(BpodSystem.GUIHandles,'DemonStartButton') && isgraphics(BpodSystem.GUIHandles.DemonStartButton)
        button = BpodSystem.GUIHandles.DemonStartButton;
        if strcmp(get(button,'String'),'Start') && ...
                strcmp(get(BpodSystem.GUIHandles.Figures.DemonFigure,'WaitStatus'),'waiting')
            if ~isempty(o.beforeStart), o.beforeStart(); end
            callback = get(button,'Callback');
            if iscell(callback)
                feval(callback{1},button,[],callback{2:end});
            else
                feval(callback,button,[]);
            end
            return
        end
    end
    if ChipmunkSessionTest.stopped || ~BpodSystem.Status.BeingUsed
        return
    end
    state = BpodSystem.Status.CurrentStateName;
    if ~strcmp(state,ChipmunkSessionTest.lastState)
        if isempty(o.trialLimit) || o.trialLimit <= 3
            fprintf('Session driver state: %s\n',state);
        elseif isfield(BpodSystem.Data,'nTrials') && mod(BpodSystem.Data.nTrials,100)==0
            fprintf('ENDURANCE_PROGRESS %d\n',BpodSystem.Data.nTrials);
        end
        ChipmunkSessionTest.lastState = state;
    end
    ports = find(BpodSystem.HW.Inputs == 'P');
    held = BpodSystem.HardwareState.InputState(ports(1:3)) ~= 0;
    nDone = 0;
    if isfield(BpodSystem.Data,'TrialSettings'), nDone = numel(BpodSystem.Data.TrialSettings); end
    act(state,nDone,held);
catch ME
    ChipmunkSessionTest.error = ME.message;
    warning('SessionTest:Driver','%s',getReport(ME,'extended','hyperlinks','off'));
    init = findall(findall(0,'Tag','ChipmunkInit'),'Style','pushbutton','String','Initialize');
    if ~isempty(init)
        close(ancestor(init(1),'figure'));
    end
    stop(driver);
    RunProtocol('Stop');
    if isfield(BpodSystem.GUIHandles,'Figures') && isfield(BpodSystem.GUIHandles.Figures,'DemonFigure') && ...
            isgraphics(BpodSystem.GUIHandles.Figures.DemonFigure)
        uiresume(BpodSystem.GUIHandles.Figures.DemonFigure);
    end
end
end

function restore(paths,folder,oldLab)
global BpodSystem
BpodSystem.Path = paths;
cd(folder);
setenv('LABDATA_PATH',oldLab);
end
