function check_stimulus_plot_parents()
global BpodSystem
original=BpodSystem;root=fileparts(fileparts(mfilename('fullpath')));oldPath=path;
addpath(fullfile(root,'Functions'));f=figure('Visible','off');
cleanup=onCleanup(@() restore(f,original,oldPath));
a=axes(f);b=axes(f);other=axes(f);
BpodSystem=struct('GUIHandles',struct(),'GUIData',struct());
% Simulate an ephys redraw changing current axes between setup and line creation.
l1=addlistener(a,'XLim','PostSet',@(~,~) axes(other));
l2=addlistener(b,'XLim','PostSet',@(~,~) axes(other));
StimulusPlotDemonstrator(a,b,'init',100,2);
assert(isequal(BpodSystem.GUIHandles.StimulusPlotVisualLine.Parent,a));
assert(isequal(BpodSystem.GUIHandles.StimulusPlotAuditoryLine.Parent,b));
cla(other);StimulusPlotDemonstrator(a,b,'refresh',zeros(2,200));
delete(l1);delete(l2);
fprintf('PASS: stimulus lines retain their axes across interleaved ephys redraws\n');
end
function restore(f,original,oldPath)
global BpodSystem
if isgraphics(f),delete(f);end
BpodSystem=original;path(oldPath);
end
