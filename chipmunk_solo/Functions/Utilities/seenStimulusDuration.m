function seen = seenStimulusDuration(states)
% Seconds of stimulus the mouse saw in an active trial.
% The task starts the stimulus at PlayStimulus and stops it (SoftCode 255) when
% the trial reaches its outcome. Inf when no outcome state was reached.
onset = states.PlayStimulus(1,1);
seen = inf;
for name = {'DemonReward', 'DemonWrongChoice', 'DemonDidNotChoose'}
    if isfield(states, name{1}) && isfinite(states.(name{1})(1,1))
        seen = min(seen, states.(name{1})(1,1) - onset);
    end
end
end
