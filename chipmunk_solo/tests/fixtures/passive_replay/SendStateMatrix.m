function SendStateMatrix(sma)
global ReplayTest BpodSystem
assert(isequal(cellfun(@(s) s.Name,sma.States,'UniformOutput',false), ...
    {'Sync','InterTrialInterval','PlayStimulus','StopStimulus','FinishTrial'}));
ReplayTest.matrix = sma;
if ~isfield(ReplayTest, 'firstMatrix')
    ReplayTest.firstMatrix = sma;
    if isfield(ReplayTest, 'activeTrialEnd')
        ReplayTest.firstSentElapsed = toc(ReplayTest.activeTrialEnd);
    end
end
BpodSystem.StateMatrix.StateNames = cellfun(@(s) s.Name,sma.States,'UniformOutput',false);
end
