function data = AddTrialEvents(data, events)
if isfield(data,'nTrials')
    data.nTrials = data.nTrials + 1;
else
    data.nTrials = 1;
end
data.RawEvents.Trial{data.nTrials} = events;
end
