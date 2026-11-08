function sma = AddState(sma, varargin)
state = struct();
for k = 1:2:numel(varargin)
    state.(varargin{k}) = varargin{k+1};
end
assert(~any(contains(string(state.StateChangeConditions), 'Port')));
assert(~any(contains(string(state.OutputActions(1:2:end)), 'Valve')));
sma.States{end+1} = state;
end
