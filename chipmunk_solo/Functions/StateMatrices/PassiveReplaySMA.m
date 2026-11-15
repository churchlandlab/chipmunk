function sma = PassiveReplaySMA(stimDuration, interTrialInterval)
% sma = PassiveReplaySMA(stimDuration, interTrialInterval)
%
% No-choice state matrix for passive stimulus replay. Sends a sync TTL,
% waits the source trial's inter-trial interval, plays SoftCode 1, waits
% for the stimulus to finish, then stops with SoftCode 255 and exits.
% Does not wait on ports, rewards, punishments, or fixation.
%
% INPUTS:
%   stimDuration       - seconds to remain in the PlayStimulus state
%   interTrialInterval - seconds to wait after Sync before playback
%                        (from the source trial's saved trial delays)
%
% OUTPUT: sma - Bpod state matrix
%
%--------------------------------------------------------------------------

if nargin < 1 || isempty(stimDuration) || ~isfinite(stimDuration) || stimDuration <= 0
    stimDuration = 1;
end
if nargin < 2 || isempty(interTrialInterval) || ~isfinite(interTrialInterval) || interTrialInterval < 0
    interTrialInterval = 0;
end

sma = NewStateMatrix();

sma = AddState(sma, 'Name', 'Sync', ...
    'Timer', 0.1, ...
    'StateChangeConditions', {'Tup', 'InterTrialInterval'}, ...
    'OutputActions', {'BNC2', 1});
% TTL for camera / ephys sync at the start of each replay trial.
% Order matches the active task: Sync, then ITI, then stimulus.

sma = AddState(sma, 'Name', 'InterTrialInterval', ...
    'Timer', interTrialInterval, ...
    'StateChangeConditions', {'Tup', 'PlayStimulus'}, ...
    'OutputActions', {});
% Replay the source trial's saved inter-trial interval before playback.

sma = AddState(sma, 'Name', 'PlayStimulus', ...
    'Timer', stimDuration, ...
    'StateChangeConditions', {'Tup', 'StopStimulus'}, ...
    'OutputActions', {'SoftCode', 1});
% SoftCode 1 starts the pre-loaded stimulus on PsychToolboxSoundServer.

sma = AddState(sma, 'Name', 'StopStimulus', ...
    'Timer', 0.05, ...
    'StateChangeConditions', {'Tup', 'FinishTrial'}, ...
    'OutputActions', {'SoftCode', 255});
% SoftCode 255 stops any remaining playback before exit.

sma = AddState(sma, 'Name', 'FinishTrial', ...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup', '>exit'}, ...
    'OutputActions', {});
end
