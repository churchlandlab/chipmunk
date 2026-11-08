function check_settings_compatibility(settingsFolder)
% Read saved settings, exercise the real GUI and save only temporary copies.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1
    settingsFolder = fullfile(root,'Experiments');
end
global BpodSystem update
oldBpod = BpodSystem;
oldUpdate = update;
oldPath = path;
cleanup = onCleanup(@() restore(oldBpod,oldUpdate,oldPath));
addpath(genpath(fullfile(root,'Functions')));
files = dir(fullfile(settingsFolder,'**','*.mat'));
checked = 0;
placeholders = 0;
for k = 1:numel(files)
    source = fullfile(files(k).folder,files(k).name);
    loaded = load(source);
    assert(isfield(loaded,'ProtocolSettings'), 'Missing ProtocolSettings: %s',source);
    original = loaded.ProtocolSettings;
    if isempty(fieldnames(original))
        placeholders = placeholders + 1; % Bpod creates empty DefaultSettings placeholders.
        continue
    end
    BpodSystem = struct('ProtocolSettings',original,'GUIHandles',struct());
    ensurePassiveReplaySettings();
    ensureStimulusManipulationSettings();
    if ~isfield(BpodSystem.ProtocolSettings,'baseWait')
        BpodSystem.ProtocolSettings.baseWait = .5;
    end
    % Metadata normally collected by initChipmunk; no devices or paths are opened.
    if ~isfield(BpodSystem.ProtocolSettings,'demonID')
        BpodSystem.ProtocolSettings.demonID = 'FakeSubject';
    end
    if ~isfield(BpodSystem.ProtocolSettings,'demonWeight')
        BpodSystem.ProtocolSettings.demonWeight = 25;
    end
    expected = BpodSystem.ProtocolSettings;
    BpodSystem.Data = struct('OutcomeRecord',[],'ValidTrials',[],'CorrectResponse',[], ...
        'EarlyWithdrawal',[],'DidNotChoose',[],'LeftSideRewardAmount',0,'RightSideRewardAmount',0);
    DemonstratorFigure('init');
    fig = BpodSystem.GUIHandles.Figures.DemonFigure;
    figCleanup = onCleanup(@() deleteIfValid(fig));
    actual = DemonstratorFigure('update',expected);
    assertSameValues(expected,actual,source);
    file = [tempname '.mat'];
    fileCleanup = onCleanup(@() deleteIfPresent(file));
    BpodSystem.Path.Settings = file;
    button = BpodSystem.GUIHandles.DemonSaveButton;
    callback = get(button,'Callback');
    if iscell(callback)
        feval(callback{1},button,[],callback{2:end});
    else
        feval(callback,button,[]);
    end
    saved = load(file);
    assertSameValues(expected,saved.ProtocolSettings,source);
    unchanged = load(source);
    assertSameValues(original,unchanged.ProtocolSettings,source);
    checked = checked + 1;
    clear figCleanup fileCleanup
end
assert(checked > 0,'No configured settings files found.');
fprintf('PASS: %d settings GUI/Update/Save round trips; %d empty placeholders skipped\n',checked,placeholders);
end

function assertSameValues(expected,actual,source)
names = fieldnames(expected);
for k = 1:numel(names)
    name = names{k};
    a = expected.(name);
    b = actual.(name);
    if isnumeric(a) && isnumeric(b)
        a = double(a);
        b = double(b);
    end
    assert(isequaln(a,b),'Setting %s changed in %s',name,source);
end
end

function deleteIfValid(fig)
if isgraphics(fig), delete(fig); end
end

function deleteIfPresent(file)
if isfile(file), delete(file); end
end

function restore(oldBpod,oldUpdate,oldPath)
global BpodSystem update
BpodSystem = oldBpod;
update = oldUpdate;
path(oldPath);
end
