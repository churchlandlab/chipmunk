function check_psychometric_plot
% Run in a fresh MATLAB session; no Bpod hardware is needed.
global BpodSystem
assert(isempty(BpodSystem), 'Run this check in a fresh MATLAB session.');
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'Functions'));
BpodSystem = struct();
BpodSystem.ProtocolSettings.highRateSide = 'R';
fig = figure('Position', [100 100 780 650]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
tabs = uitabgroup(fig);
tab = uitab(tabs);
otherTab = uitab(tabs);
ax = axes('Parent', tab, 'Position', [0.1 0.31 0.2 0.2], 'NextPlot', 'add');

lastwarn('');
PsychometricPlotDemonstrator(ax, 'init');
otherAxes = axes('Parent', tab, 'Position', [0.4 0.31 0.2 0.2]);
scatter(otherAxes, nan, nan);
drawnow;
[message, ~] = lastwarn;
assert(isempty(message), message);

BpodSystem.Data.ValidTrials = [1 1 1 1 1 1 1 1 1 0];
BpodSystem.Data.Modality = [1 1 1 1 2 2 3 3 3 2];
BpodSystem.Data.ResponseSide = [0 1 1 0 1 0 0 1 1 1];
BpodSystem.Data.StimulusRate = [4 nan; 4 nan; 8 nan; 12 nan; ...
    nan 20; nan 20; 6 6; 6 6; 18 18; nan 4];
PsychometricPlotDemonstrator(ax, 'refresh');
lines = [BpodSystem.GUIHandles.VisualPsychometricLine, ...
    BpodSystem.GUIHandles.AuditoryPsychometricLine, ...
    BpodSystem.GUIHandles.MultiSensoryPsychometricLine];
expectedX = {[4 8 12], 20, [6 18]};
expectedY = {[0.5 1 0], 0.5, [0.5 1]};
for modality = 1:3
    assert(isequal(lines(modality).XData(:), expectedX{modality}(:)));
    assert(isequal(lines(modality).YData(:), expectedY{modality}(:)));
end

lg = BpodSystem.GUIHandles.PsychometricPlotLegend;
assert(strcmp(lg.Location, 'northwest'));
BpodSystem.ProtocolSettings.highRateSide = 'L';
BpodSystem.Data.ValidTrials(5:end) = 0;
PsychometricPlotDemonstrator(ax, 'refresh');
assert(strcmp(lg.Location, 'northeast'));
assert(isempty(lines(2).XData) && isempty(lines(2).YData));
assert(isempty(lines(3).XData) && isempty(lines(3).YData));
line(ax, [0 24], [0.5 0.5]);
assert(numel(lg.String) == 3);

lastwarn('');
for k = 1:3
    tabs.SelectedTab = otherTab;
    drawnow;
    tabs.SelectedTab = tab;
    fig.Position(3) = 780 + 20*k;
    drawnow;
end
[message, ~] = lastwarn;
assert(isempty(message), message);
fprintf('PSYCHOMETRIC_PLOT_CHECK_PASSED\n');
end
