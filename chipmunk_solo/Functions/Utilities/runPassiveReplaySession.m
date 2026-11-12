function runPassiveReplaySession(samplingFreq, udplabcams, activeTrialEnd)
% Replay what the mouse saw in trials that reached PlayStimulus without an early withdrawal.
% Keep replay events separate from active trials, including partial attempts.
global BpodSystem
if nargin < 3 || isempty(activeTrialEnd)
    activeTrialEnd = tic;
end
replay = struct('sourceTrialNumbers', [], 'nRequested', 0, 'nCompleted', 0, ...
    'status', 'skipped', 'errorIdentifier', '', 'errorMessage', '', ...
    'stimDurations', [], 'interTrialIntervals', [], 'modalities', [], ...
    'trialStatus', {{}}, 'rawEvents', {{}}, 'stateNames', {{}}, 'stoppedPulseAfter', []);
cleanup = onCleanup(@stopReplay);
try
    syncPassiveReplaySettingsFromGui();
    s = BpodSystem.ProtocolSettings;
    validateattributes(s.passiveReplayEnable, {'numeric', 'logical'}, {'scalar', 'finite', 'binary'});
    if ~s.passiveReplayEnable
        return
    end
    validateattributes(s.passiveReplayFraction, {'numeric'}, {'scalar', 'finite', '>=', 0, '<=', 1});
    if ~isempty(s.passiveReplayNTrials)
        validateattributes(s.passiveReplayNTrials, {'numeric'}, {'scalar', 'nonnegative', 'nonnan'});
    end
    order = validatestring(s.passiveReplayOrder, {'sequential', 'random'});
    replay.order = order;
    replay.fraction = s.passiveReplayFraction;
    sources = [];
    if isfield(BpodSystem.Data, 'RawEvents')
        trials = BpodSystem.Data.RawEvents.Trial;
        for t = 1:numel(trials)
            states = trials{t}.States;
            played = isfield(states, 'PlayStimulus') && any(isfinite(states.PlayStimulus(:,1)));
            withdrew = isfield(states, 'DemonEarlyWithdrawal') && any(isfinite(states.DemonEarlyWithdrawal(:,1)));
            if played && ~withdrew
                sources(end+1) = t; %#ok<AGROW>
            end
        end
    end
    count = round(numel(sources) * s.passiveReplayFraction);
    if ~isempty(s.passiveReplayNTrials)
        count = min(count, round(s.passiveReplayNTrials));
    end
    if strcmp(order, 'random')
        sources = sources(randperm(numel(sources), count));
    else
        sources = sources(1:count);
    end
    replay.sourceTrialNumbers = sources;
    replay.nRequested = count;
    replay.stimDurations = nan(1, count);
    replay.interTrialIntervals = nan(1, count);
    replay.modalities = nan(1, count);
    replay.trialStatus = repmat({'not_started'}, 1, count);
    replay.rawEvents = cell(1, count);
    if count == 0
        BpodSystem.Data.PassiveReplay = replay;
        return
    end

    BpodSystem.Status.BeingUsed = 1;
    replay.status = 'running';
    if ephysRecordingEnabled(s)
        spikeglx_client('log',sprintf('Passive replay started: %d source trials',count));
    end
    for r = 1:count
        if BpodSystem.Status.BeingUsed == 0
            replay.status = 'aborted';
            break
        end
        source = sources(r);
        replay.trialStatus{r} = 'preparing';
        [signal, duration] = rebuildTrialStimSignals(source, samplingFreq);
        % Replay what the mouse saw: the task stopped the train at the trial outcome.
        seen = seenStimulusDuration(BpodSystem.Data.RawEvents.Trial{source}.States);
        if seen < duration
            signal = signal(:, 1:max(1, round(seen * samplingFreq)));
            duration = size(signal, 2) / samplingFreq;
        end
        iti = BpodSystem.Data.TrialDelays(source).interTrialInterval;
        validateattributes(iti, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
        replay.stimDurations(r) = duration;
        replay.modalities(r) = BpodSystem.Data.Modality(source);
        PsychToolboxSoundServer('Load', 1, signal);
        if r == 1
            % Sync plus the remaining wait targets onset 1 s after activeTrialEnd (the task checkpoint save).
            iti = max(0, 1 - toc(activeTrialEnd) - 0.1);
        end
        replay.interTrialIntervals(r) = iti;
        SendStateMatrix(PassiveReplaySMA(duration, iti));
        % Stop can arrive while preparing a waveform or sending the matrix.
        drawnow;
        if BpodSystem.Status.BeingUsed == 0
            replay.trialStatus{r} = 'aborted';
            replay.status = 'aborted';
            break
        end
        logReplay(sprintf('passive_replay_start:%d<-%d', r, source));
        replay.trialStatus{r} = 'running';
        assertChipmunkRecording();
        events = RunStateMatrix;
        replay.stateNames = BpodSystem.StateMatrix.StateNames;
        replay.rawEvents{r} = events;
        logReplay(sprintf('passive_replay_end:%d<-%d', r, source));
        % RunStateMatrix returns numeric state IDs; AddTrialEvents names them later.
        finishState = find(strcmp(replay.stateNames, 'FinishTrial'), 1);
        if isfield(events, 'States') && ~isempty(finishState) && any(events.States == finishState)
            replay.trialStatus{r} = 'completed';
            replay.nCompleted = replay.nCompleted + 1;
        elseif BpodSystem.Status.BeingUsed == 0
            replay.trialStatus{r} = 'aborted';
            replay.status = 'aborted';
            % This replay's Sync pulse was sent but the replay did not finish.
            replay.stoppedPulseAfter = replay.nCompleted;
            break
        else
            error('PassiveReplay:IncompleteTrial', 'Replay trial %d returned without FinishTrial.', r);
        end
    end
    if strcmp(replay.status, 'running')
        replay.status = 'completed';
    end
catch ME
    replay.status = 'failed';
    replay.errorIdentifier = ME.identifier;
    replay.errorMessage = ME.message;
    if exist('r', 'var')
        replay.trialStatus{r} = 'failed';
    end
    warning('PassiveReplay:Failed', 'Passive replay ended early: %s', ME.message);
end
BpodSystem.Data.PassiveReplay = replay;
if ephysRecordingEnabled(BpodSystem.ProtocolSettings)
    spikeglx_client('log',sprintf('Passive replay %s: %d/%d completed',replay.status,replay.nCompleted,replay.nRequested));
end

    function logReplay(message)
        if ~isempty(udplabcams)
            try
                labcamsCommand(udplabcams, ['log=' message],false);
            catch ME
                warning('PassiveReplay:LogFailed', 'Could not log replay: %s', ME.message);
            end
        end
    end
end

function stopReplay()
% A separate workspace keeps the guard valid even when its caller unwinds.
global BpodSystem
BpodSystem.Status.BeingUsed = 0;
try
    PsychToolboxSoundServer('stopAll');
catch ME
    warning('PassiveReplay:StopFailed', 'Could not stop playback: %s', ME.message);
end
end
