function events = runTrialStateMatrix()
% RunStateMatrix with the SpikeGLX trace timer paused: its fetch and redraw delay soft codes.
traces = timerfind('Name', 'SpikeGLXTraces', 'Running', 'on');
if ~isempty(traces)
    stop(traces);
end
resume = onCleanup(@() restartTimers(traces)); %#ok<NASGU>
events = RunStateMatrix;
end

function restartTimers(traces)
if ~isempty(traces)
    start(traces(isvalid(traces))); % shutdown may have deleted it
end
end
