function chipmunk_solo(maxTrialNum)
if nargin < 1
    maxTrialNum = 5000;
end
validateattributes(maxTrialNum, {'numeric'}, {'scalar','integer','>=',1,'<=',5000});

global BpodSystem

%Add the path to the external functions for chipmunk
addpath(genpath(fullfile(BpodSystem.Path.ProtocolFolder,'chipmunk_solo','Functions')));
addpath(fullfile(BpodSystem.Path.ProtocolFolder,'chipmunk_solo','vendor','SpikeGLX-MATLAB-SDK','API'));

%% Initialize the protocol
%Load the settings for the respective experiment and start the protocol
initChipmunk;
ensurePassiveReplaySettings();
ensureStimulusManipulationSettings();
ensureOptionalRecordingSettings();
S = BpodSystem.ProtocolSettings;
ephysOn = ephysRecordingEnabled(S);
if ~isfield(S, 'baseWait') %Settings saved before baseWait existed ran the half-second task
    S.baseWait = 0.5;
    BpodSystem.ProtocolSettings.baseWait = S.baseWait;
end
%% Decide on the sound handling

%Find sound card for stimuli
PsychToolboxSoundServer('init'); % Try and let this crash before all the other inputs are passed

%Set soft code handler to trigger sounds
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';

SamplingFreq = 192000; %The frequency of the (Fenix) sound card

[subjectFolder,bhvFile,~] = fileparts(BpodSystem.Path.CurrentDataFile{1});
%% Start labcams
udplabcams = [];
if ephysOn,BpodSystem.PluginObjects.labcams=[];end
if isfield(BpodSystem.ProtocolSettings,'labcamsAddress') && ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
    try %could be assigned but if no camera available it will throw an error
        tmp = strsplit(BpodSystem.ProtocolSettings.labcamsAddress,':');
        udpAddress = tmp{1};
        udpPort = str2double(tmp{2});
        udplabcams = udp(udpAddress,udpPort);
        udplabcams.Timeout = 2;
        fopen(udplabcams);
        launchCommand = labcamsLaunchCommand(BpodSystem.ProtocolSettings.labcamsConfig);
        % Check whether an existing app must reload the explicitly selected config.
        fwrite(udplabcams,'ping');
        reply = fgetl(udplabcams);
        if ~isempty(reply) && ~isempty(BpodSystem.ProtocolSettings.labcamsConfig)
            fwrite(udplabcams,'quit=1');
            udplabcams.Timeout = .5;
            closed = false;
            for attempt = 1:10
                pause(.25);
                flushinput(udplabcams);
                fwrite(udplabcams,'ping');
                if isempty(fgetl(udplabcams))
                    closed = true;
                    break
                end
            end
            assert(closed, 'chipmunk_solo:CameraRestart', ...
                'Could not close labcams to apply the selected configuration.');
            reply = '';
            udplabcams.Timeout = 2;
        end
        if ~isempty(reply)
            disp(' -> labcams connected.');
        else
            disp(' -> starting labcams');
            status = system(launchCommand);
            assert(status == 0, 'chipmunk_solo:CameraLaunch', 'Could not launch labcams.');
            udplabcams.Timeout = 5;
            for i = 1:5
                fwrite(udplabcams,'ping');
                reply = fgetl(udplabcams);
                if ~isempty(reply)
                    break
                end
            end
            if isempty(reply)
                error('labcams did not respond to ping.');
            end
        end
        udplabcams.Timeout = 2;
        % Always configure this session, including when labcams was already open.
        fwrite(udplabcams,'softtrigger=0'); fgetl(udplabcams);
        fwrite(udplabcams,'manualsave=0'); fgetl(udplabcams);
        fwrite(udplabcams,['expname=' fullfile(subjectFolder,bhvFile)]); fgetl(udplabcams);
        fwrite(udplabcams,'load_reference=/home/anne/reference_image'); fgetl(udplabcams);
        if ephysOn
            BpodSystem.PluginObjects.labcams = udplabcams;
        else
            fwrite(udplabcams,'softtrigger=1'); fgetl(udplabcams);
        end
    catch
        if ~isempty(udplabcams)
            delete(udplabcams);
            udplabcams = [];
        end
        warning('A problem occurred with labcams, no video will be recorded')
    end
end
if ephysOn
    [sessionFolder,~,~] = fileparts(subjectFolder);
    [~,sessionSpecifier] = fileparts(sessionFolder);
    spikeglx_client('set','host',S.spikeGLXHost);
    spikeglx_client('init','ephys',S.demonID,sessionSpecifier);
    SpikeGLXControl('init');
end
%% Get the polynomial coefficients of the sound calibration
soundCalibration = load(fullfile(BpodSystem.Path.LocalDir,'Calibration Files','WhiteNoiseCalibration.mat'));
S.soundCalibrationModelParams = polyfit(reshape(soundCalibration.TargetSPLs,1,[]),reshape(10*log10(soundCalibration.NoiseAmplitudes),1,[]),1);
%% Task control sounds and static task parameters
% Set up the task cue sounds and parameters that don't usually change unless
% the user updates them via the the GUI.

% Generate the sounds that signal task-related information and upload them
% to the soundcard (not the stimuli though). In this implementation the
% trial start cue and the go cue after fixation are generated at the same
% loudness (S.goCueLoudness).

% Fixed stimulus properties that remain unchanged
stimTrainDuration = 1;
%% Randomly draw trial sides and pre-assign bias arrays
%Generate a random list of trial sides based on the porportion of left
%choices in the settings.
TrialSidesList = double(rand(1,maxTrialNum) > S.propLeft); %Right side trials will be assigned 1 and left trials 0
% IMPORTANT: get as double so that it does not mess up other functions

%Prealocate variables for the anti bias functions
trialHistoryBiases = 0.5 * ones(2, 2, 2);
%This array captures the estimated propensity of an animal to choose one
%side or another given the same choice context. For instance having
%correctly done a left choice and being asked to do a right choice now.
%Rows are left or right choices made by the animal, columns are incorrect
%or correct selection during the previous trial and "sheets" are the
%correct side of the trial that is currently running, L and R.

modalityBiases = 0.5 * ones(1, 3);
%Keep track of the side biases that might be due to the modality of the
%stimulus. Columns are visual, auditory, multi-sensory

lastValidCorrectSide = NaN;
lastValidResponseSide = NaN;
lastValidOutcome = NaN;
%These variables store the trial and outcome information for the last trial
%that was completed and are updated at the end. This serves to update the
%anti-bias arrays and identify biases across invalid trials.

prevPropLeft = S.propLeft; %store this value to update the sides list if necessary
%% Dummy state matrix
% Build an initial state matrix for the task diagram.
[sma, ~, reviseChoiceFlag, pacedFlag] = feval(BpodSystem.ProtocolSettings.smaAssembler);
ModalityRecord = nan(1,maxTrialNum);
%% Initialize arrays for storing values and display
BpodSystem.Data.OutcomeRecord = NaN;
BpodSystem.Data.Rewarded = 0;
BpodSystem.Data.EarlyWithdrawal = 0;
BpodSystem.Data.DidNotChoose = 0;
BpodSystem.Data.DidNotInitiate = 0;
BpodSystem.Data.ResponseSide = NaN;
BpodSystem.Data.Modality = NaN;
BpodSystem.Data.CorrectSide = NaN;
BpodSystem.Data.ValidTrials = 0;
BpodSystem.Data.LeftSideRewardAmount = 0; %The cumulatively harvested amount of water on the left side, a scalar
BpodSystem.Data.RightSideRewardAmount = 0;
BpodSystem.Data.CorrectResponse = 0;
%Arrays with a zero do alreay contain information that is read out by
%refreshing the figures whereas the NaN containing variables are yet
%undefined

BpodSystem.Data.TaskPhase = BpodSystem.ProtocolSettings.experimentName;
BpodSystem.Data.ReviseChoiceFlag = reviseChoiceFlag;
BpodSystem.Data.PacedFlag = pacedFlag;
%% Initialize GUI and plots

%initialize the main figure
DemonstratorFigure('init');

%Set up the plots for the main figure
StimulusPlotDemonstrator(BpodSystem.GUIHandles.StimulusPlotV, BpodSystem.GUIHandles.StimulusPlotA, 'init', SamplingFreq, stimTrainDuration);
outcomePlotLimits = OutcomePlotDemonstrator(BpodSystem.GUIHandles.OutcomePlotDemonstrator, 'init', TrialSidesList);
PerformancePlotDemonstrator(BpodSystem.GUIHandles.PerformancePlotDemonstrator,'init',outcomePlotLimits);
PsychometricPlotDemonstrator(BpodSystem.GUIHandles.PsychometricPlotDemonstrator,'init');
WaitTimeDiffPlotDemonstrator(BpodSystem.GUIHandles.WaitTimeDiffPlotDemonstrator,'init',true);
StateMachineLogicPlot(sma, BpodSystem.GUIHandles.StateLogic);

%Initialize the notook to keep track of unexpected events, etc.
BpodNotebook('init');
%% Prepare the trial loop

TrialsDone =  0; %This is the number of already finished trials and is by definition currentTrial-1
global update
update = 1; %Define the update variable and make sure that we retrieve some changes made at the startup.

if BpodSystem.Status.BeingUsed %only run this code if protocol is still active
    disp('Set the camera and hit start')
    uiwait(BpodSystem.GUIHandles.Figures.DemonFigure); %Wait for the user to click start
    if ~BpodSystem.Status.BeingUsed
        finishSession();
        return
    end
else
    if ephysOn
        SpikeGLXControl('shutdown');
        spikeglx_client('shutdown');
    end
    return %Peacefully stop execution if the Bpod was switched off up to here.
end
%% Start saving labcams if connected
% Ephys sessions wait for SpikeGLX Enable recording before cameras write.
if ~isempty(udplabcams) && ~ephysOn
    fwrite(udplabcams,'softtrigger=0')
    pause(1)
    fgetl(udplabcams);
    fwrite(udplabcams,'manualsave=1')
    fgetl(udplabcams);
    fwrite(udplabcams,'softtrigger=1')
    fgetl(udplabcams);
end

pause(0.5) %Introduce a small break before starting the trials. This gives
%labcams enough time to get started and record at least one non-trial frame
%%
tstart = tic;
for currentTrial = 1:maxTrialNum
    try %This is to make sure that the data will be saved even if some error occurs during its execution
        disp("---------------New Loop Starts!---------------");
        tic
        %% Check for user-inputs and change display of automatically changing
        %parameters on the figures.
        if update == 1 || TrialsDone == 0
            previousSettings = S;
            S = DemonstratorFigure('update', S);
            % Apply pending GUI edits only when preparing a new trial.
            if TrialsDone > 0
                appendTrialNote(currentTrial, settingsChangeNote(previousSettings, S));
            end
            update = 0; %Finish updating
        end

        % Refresh automatic values without overwriting pending edits.
        DemonstratorFigure('refresh', S); %Do this only after updating the user input to  avoid overriding it!
        %% Randomly select the stimulus modality for the current trial
        ModalityRecord(currentTrial) = drawStimModality;
        %% Check trial side and redraw according to user changes and biases

        if prevPropLeft ~= S.propLeft
            remainingTrialNum = maxTrialNum - TrialsDone;
            TrialSidesList(currentTrial:maxTrialNum) = double(rand(1,remainingTrialNum) > S.propLeft); %Redraw the sides
            prevPropLeft = S.propLeft; %Retain this left side probability to compare the next time
            outcomePlotLimits = OutcomePlotDemonstrator(BpodSystem.GUIHandles.OutcomePlotDemonstrator, 'refresh',...
                currentTrial,TrialSidesList,BpodSystem.Data.OutcomeRecord); %Update the display if changed
        end

        %Check the biases the animal has for choice and outcome history, and modality and
        %change the proportion of left trials according to these biases and the
        %antiBiasStrength factor.
        if S.antiBiasStrength > 1
            S.antiBiasStrength = 1;
        elseif S.antiBiasStrength < 0
            S.antiBiasStrength = 0;
        end

        if TrialsDone > 1 %Make sure to have some choice history
            if BpodSystem.Data.OutcomeRecord(TrialsDone) > -1 && BpodSystem.Data.OutcomeRecord(TrialsDone) < 2 %
                %This is to discard no-initiation trials and early withdrawals (-2 & -1)
                %and no-choice (2) trials.
                if S.antiBiasStrength > 0
                    pLeft = getAntiBiasPLeft(trialHistoryBiases, modalityBiases, ModalityRecord(currentTrial), ...
                        S.antiBiasStrength, BpodSystem.Data.ResponseSide(TrialsDone), BpodSystem.Data.OutcomeRecord(TrialsDone));
                    %Get the new left side probability. CurrentTrial refers to
                    %the upcoming not yet completed trial, while trials done
                    %is the index of the last completed one.
                    TrialSidesList(currentTrial) = double(rand > pLeft); %Changed from original more complicated: rand > (1-S.propLeft);

                    outcomePlotLimits = OutcomePlotDemonstrator(BpodSystem.GUIHandles.OutcomePlotDemonstrator, 'refresh',...
                        currentTrial,TrialSidesList,BpodSystem.Data.OutcomeRecord); %Update the display if changed
                end
            end
        end
        %% Find the frequency of the stimulus given the assigned side and modality

        % First define the category boundary for this type of trial
        if BpodSystem.ProtocolSettings.isPoissonStim == 0
            categoryBoundary = 12.5;    %events/s for the two-interval rate task
        else
            categoryBoundary = 12; %For the poisson rate task
        end

        % Find a stimulus rate associated with the designated correct side
        stimulusRate = findStimRate(TrialSidesList(currentTrial), ModalityRecord(currentTrial));
        %% Generate the stim train according to the chosen frequency and specified task design

        % Specify the duration of the stimulus train and of the individual stimulus
        stimTrainDuration = 1; %In s
        trialStim = resolveTrialStimulusParams(stimulusRate);
        stimulusDuration = trialStim.stimulusDuration;
        minInterval = trialStim.minInterval;
        trialBrightness = trialStim.brightness;

        if BpodSystem.ProtocolSettings.isPoissonStim
            interStimulusIntervalList = poissonStimulusTrain(stimTrainDuration, stimulusDuration, minInterval, stimulusRate);
            [visualIsiList, auditoryIsiList] = assignModalityIsi(ModalityRecord(currentTrial), interStimulusIntervalList, ...
                BpodSystem.ProtocolSettings.syncMultiSensory, 0, ...
                @() poissonStimulusTrain(stimTrainDuration, stimulusDuration, minInterval, stimulusRate));
        else
            if stimulusRate > 16
                stimulusRate = 16;
            end
            if stimulusRate < 9
                stimulusRate = 9;
            end
            shortInterval = 0.05;
            longInterval = 0.1;
            minInterval = shortInterval;
            interStimulusIntervalList = twoIntervalStimulusTrain(stimulusRate, shortInterval, longInterval, stimulusDuration, stimTrainDuration);
            [visualIsiList, auditoryIsiList] = assignModalityIsi(ModalityRecord(currentTrial), interStimulusIntervalList, ...
                BpodSystem.ProtocolSettings.syncMultiSensory, 0.02, ...
                @() twoIntervalStimulusTrain(categoryBoundary-0.5+round(rand), shortInterval, longInterval, stimulusDuration, stimTrainDuration));
        end
        %% Construct the stim signal and refresh plots

        %Sound parameters
        soundType = 'whiteNoise + envelope';
        addedNoiseLoudness = 10;

        %Assemble the signal
        if ModalityRecord(currentTrial) == 1 %It's a visual trial
            visualStimSignal = createVisualStimSignal(interStimulusIntervalList, SamplingFreq, trialBrightness, stimulusDuration);
            auditoryStimSignal = zeros(1,length(visualStimSignal)); %Zero-signal
        elseif ModalityRecord(currentTrial) == 2 %It's an auditory trial
            auditoryStimSignal = createAuditoryStimSignal(interStimulusIntervalList, SamplingFreq, stimulusDuration,...
                soundType, BpodSystem.ProtocolSettings.stimLoudness, addedNoiseLoudness, BpodSystem.ProtocolSettings.soundCalibrationModelParams);
            visualStimSignal = zeros(1,length(auditoryStimSignal)); %Zero-signal
        elseif ModalityRecord(currentTrial) == 3
            visualStimSignal = createVisualStimSignal(visualIsiList, SamplingFreq, trialBrightness, stimulusDuration);
            auditoryStimSignal = createAuditoryStimSignal(auditoryIsiList, SamplingFreq, stimulusDuration,...
                soundType, BpodSystem.ProtocolSettings.stimLoudness, addedNoiseLoudness, BpodSystem.ProtocolSettings.soundCalibrationModelParams);
        end

        % Two-interval multisensory timing can delay the visual channel by 20 ms.
        nSamples = max(numel(visualStimSignal),numel(auditoryStimSignal));
        visualStimSignal(end+1:nSamples) = 0;
        auditoryStimSignal(end+1:nSamples) = 0;

        %Refresh the stimulus train plots
        StimulusPlotDemonstrator(BpodSystem.GUIHandles.StimulusPlotV, BpodSystem.GUIHandles.StimulusPlotA, 'refresh', [visualStimSignal; auditoryStimSignal]);
        %% Repeat parts of the signal for an extended amount of time and upload
        %  the stimuli once finished

        stimTrainSignals =  [visualStimSignal; auditoryStimSignal]; %Concatenate here for easier treatment
        stimTrainSignals = extendStimulusTrain(stimTrainSignals, BpodSystem.ProtocolSettings.extraStimDur, SamplingFreq);

        PsychToolboxSoundServer('Load', 1, stimTrainSignals); %Upload the signal
        %% Assemble and the state matrix for the trial

        if strcmp(BpodSystem.ProtocolSettings.smaAssembler, 'PassiveVisualStimSMA')
            [sma, trialDelays, reviseChoiceFlag] = PassiveVisualStimSMA([], size(stimTrainSignals,2) / SamplingFreq);
        else
            [sma, trialDelays, reviseChoiceFlag] = feval(BpodSystem.ProtocolSettings.smaAssembler, TrialSidesList(currentTrial));
        end
        % Get the state matrix, the random delays generated inside the assembler
        % function and a logical value that indicates whether the animals can revise
        % wrong choices and whether trials are self-initiated.
        %For more info check the respective SMA function.

        generateTaskControlSounds(S.goCueLoudness, S.earlyPunishLoudness, S.earlyPunishTimeout,...
            S.wrongPunishLoudness, S.wrongPunishTimeout, S.soundCalibrationModelParams, trialDelays)

        % Stop may arrive during GUI redraws while the next trial is prepared.
        if BpodSystem.Status.BeingUsed == 0
            finishSession();
            return
        end
        SendStateMatrix(sma); %Send to Bpod
        %% Display preparation time

        % After all is prepared check the time to prepare
        if currentTrial > 1 %Only display updating time from the second trial on
            fprintf('Time to retrieve data, update plots and prepare trial number %d: %d seconds\n',round(currentTrial),toc(preparationTime));
            fprintf('----------------------------------------------------------------------------\n\n');
        end
        %% Add to the camera log and run the state machine
        if ~isempty(udplabcams)
            fwrite(udplabcams,sprintf('log=trial_start[%4.0f]: %d',toc(tstart)/60,currentTrial))
        end

        assertChipmunkRecording();
        RawEvents = RunStateMatrix; %Finally run the state matrix
        %% Retrieve the trial information to save it

        preparationTime = tic; %Start measuring the time to extract, save and prepare
        TrialsDone = TrialsDone + 1; %increment number of trials done

        % Retrieving data
        if ~isempty(fieldnames(RawEvents))
            %Incorporate trial and outcome information into the Data field inside
            %BpodSystem.
            retrieveTrialData(RawEvents,TrialsDone,TrialSidesList,trialDelays,reviseChoiceFlag, ModalityRecord,...
                stimulusDuration, stimTrainDuration, categoryBoundary,interStimulusIntervalList,visualIsiList,auditoryIsiList, ...
                trialBrightness, minInterval);
        elseif BpodSystem.Status.BeingUsed == 0
            % Stop cut this trial short. Its Sync state already sent a BNC2
            % pulse, but the trial is not saved. Record where that pulse sits:
            % after this many saved trials (and before any passive replay).
            BpodSystem.Data.StoppedTrialPulse = TrialsDone - 1;
        else
            warning('There were no events recorded for this trial!')
        end

        BpodSystem.Data = BpodNotebook('sync', BpodSystem.Data); %Store the notes with the session data
        %% Write the trial end to the labcams camlog

        if ~isempty(udplabcams)
            fwrite(udplabcams,sprintf('log=trial_end:%d',currentTrial))
        end
        %% Check on Bpod status and save and close if not used anymore

        if BpodSystem.Status.BeingUsed == 0
            finishSession();
            return;
        end
        %% Update wait time and bias arrays according to
        %  the outcome of the trial that was just completed.

        % If previous trial was not an early withdrawal, increase wait duration
        if strcmpi(S.minWaitTime,'Exp') %There are no more wait time steps once the exponential delay mode has been reached.
            S.minWaitTimeStep = 0;
        elseif S.minWaitTime >= S.baseWait + 0.1 %0.1 s is the mean extra wait in exponential mode
            S.minWaitTimeStep = 0;
            S.minWaitTime = S.baseWait + 0.1;
        else %Increase the wait times only when the mouse has been waiting successfully
            if BpodSystem.Data.OutcomeRecord(TrialsDone) > -1 % If the last trial was initiated and the animal waited long enough
                S.minWaitTime = S.minWaitTime + S.minWaitTimeStep;
            end
        end

        %Update the anti-bias arrays
        if BpodSystem.Data.ValidTrials(TrialsDone) %Only update biases if the trial has been valid, meaning a choice was made.
            if sum(BpodSystem.Data.ValidTrials) > 1 %Make sure that there is a history to the choice
                [modalityBiases, trialHistoryBiases] = updateAntiBiasArrays(...
                    modalityBiases, trialHistoryBiases, ModalityRecord(TrialsDone), BpodSystem.Data.ResponseSide(TrialsDone),...
                    BpodSystem.Data.OutcomeRecord(TrialsDone),lastValidCorrectSide, lastValidResponseSide,...
                    lastValidOutcome, BpodSystem.ProtocolSettings.antiBiasTau);
                %Here, we update our estimate of the animal's biases based on
                %the outcomes of the trial just completed and the last valid
                %trial recorded. This estimate will be used to dynamically
                %modify the probability of designating a response side.

                %Now update info to store the last valid trials
            end
            lastValidCorrectSide = BpodSystem.Data.CorrectSide(TrialsDone);
            lastValidResponseSide = BpodSystem.Data.ResponseSide(TrialsDone);
            lastValidOutcome = BpodSystem.Data.OutcomeRecord(TrialsDone);
        end
        %% Update the performance plots

        outcomePlotLimits = OutcomePlotDemonstrator(BpodSystem.GUIHandles.OutcomePlotDemonstrator, 'refresh',currentTrial+1,TrialSidesList,BpodSystem.Data.OutcomeRecord);
        PerformancePlotDemonstrator(BpodSystem.GUIHandles.PerformancePlotDemonstrator,'refresh',outcomePlotLimits);
        PsychometricPlotDemonstrator(BpodSystem.GUIHandles.PsychometricPlotDemonstrator,'refresh');
        WaitTimeDiffPlotDemonstrator(BpodSystem.GUIHandles.WaitTimeDiffPlotDemonstrator,'refresh',true);
        %% Make sure to keep the data if an error occurs
    catch ME
        warning('chipmunk_solo encountered an error and will save the data and end: %s', ME.message)
        BpodSystem.Status.BeingUsed = 0;
        errorPath=path;errorCleanup=onCleanup(@() resetConsole(errorPath));
        shutdownChipmunk();
        disp('*********************************************************************')
        disp('chipmunk ended due to an error, see below')
        rethrow(ME)
    end
end
% Exhausting the trial limit must save and close just like Stop.
finishSession();

    function finishSession()
        if BpodSystem.Status.BeingUsed
            RunProtocol('Stop'); % Natural trial-limit completion must also reset the console.
        end
        % Bpod Stop removes the protocol folder, including its sound server.
        stoppedPath = path;
        pathCleanup = onCleanup(@() resetConsole(stoppedPath));
        addpath(fileparts(mfilename('fullpath')));
        % Checkpoint the task so a MATLAB crash during replay cannot lose it (~0.06 s for 428 trials).
        % shutdownChipmunk writes the final file.
        if ~isempty(BpodSystem.Path.CurrentDataFile)
            SessionData = BpodSystem.Data;
            save(BpodSystem.Path.CurrentDataFile{1},'SessionData');
        end
        % The first replay onset targets 1 s after the checkpoint is complete.
        runPassiveReplaySession(SamplingFreq, udplabcams, tic);
        shutdownChipmunk();
    end

    function resetConsole(stoppedPath)
        pathCleanup = onCleanup(@() path(stoppedPath));
        % Replay's RunStateMatrix restores Bpod's Pause icon and running state.
        RunProtocol('Stop');
    end

    function shutdownChipmunk()
        % ponytail: one shutdown for the stop button and for errors.
        % Keep ephys acquiring through behavioral saving and camera/sound cleanup.
        streamCleanup=onCleanup(@() finishStreams(ephysOn,udplabcams));
        mergeSettingsNotes();
        SessionData = BpodSystem.Data;
        passiveFolder = '';
        if ~isempty(BpodSystem.Path.CurrentDataFile)
            save(BpodSystem.Path.CurrentDataFile{1},'SessionData')
            % The task file keeps PassiveReplay because it owns the Bpod clock and every sync pulse.
            % The copy in chipmunk_passive/ is the separate passive-stimulation dataset.
            if isfield(BpodSystem.Data,'PassiveReplay') && BpodSystem.Data.PassiveReplay.nRequested > 0
                PassiveReplay = BpodSystem.Data.PassiveReplay;
                [taskFolder,taskName] = fileparts(BpodSystem.Path.CurrentDataFile{1});
                passiveFolder = fullfile(fileparts(taskFolder),'chipmunk_passive');
                [~,~] = mkdir(passiveFolder);
                save(fullfile(passiveFolder,[taskName '.mat']),'PassiveReplay');
            end
            trializedNoteIdx = [];
            for noteIdx = 1:length(BpodSystem.Data.Notes)
                if ~isempty(BpodSystem.Data.Notes{noteIdx})
                    trializedNoteIdx(end+1) = noteIdx;
                end
            end
            if ~isempty(trializedNoteIdx)
                notesFile = fopen(fullfile(fileparts(BpodSystem.Path.CurrentDataFile{1}), 'notes.txt'), 'w');
                for noteIdx = 1:length(trializedNoteIdx)
                    fprintf(notesFile, 'Trial %d: %s\n', trializedNoteIdx(noteIdx), ...
                        BpodSystem.Data.Notes{trializedNoteIdx(noteIdx)});
                end
                fclose(notesFile);
            end
        end
        clear streamCleanup % Stop all streams before offering upload.
        if ~strcmpi(BpodSystem.ProtocolSettings.demonID,'FakeSubject')
            fPath = fileparts(BpodSystem.Path.CurrentDataFile{1});
            upload = ['labdata put ' fPath ' --ask'];
            if ~isempty(passiveFolder)
                upload = [upload '; labdata put ' passiveFolder ' --ask']; % put takes one folder.
            end
            system(['export LD_LIBRARY_PATH=""; gnome-terminal -- bash -c "' upload '"']);
        end
        if isfield(BpodSystem.GUIHandles,'DemonStartButton') && isgraphics(BpodSystem.GUIHandles.DemonStartButton)
            set(BpodSystem.GUIHandles.DemonStartButton,'String','Finished','Enable','off');
        end
    end
    function finishStreams(ephysEnabled,camera)
        ephysCleanup=onCleanup(@() finishEphys(ephysEnabled));
        if ephysEnabled
            [cameraOK,cameraError]=labcams_ephys('stop');
            if ~cameraOK,warning('chipmunk_solo:CameraStop','%s',cameraError);end
        end
        try
            if ~isempty(camera)
                fwrite(camera,sprintf('log=end')); fgetl(camera);
                fwrite(camera,sprintf('softtrigger=0')); fgetl(camera);
                fwrite(camera,sprintf('manualsave=0')); fgetl(camera);
                pause(1)
                fwrite(camera,sprintf('quit=1'));
                fclose(camera);
                delete(camera);
                camera = [];
            end
        catch
            warning('Could not close labcams cleanly; saving behavioral data.');
        end
        PsychToolboxSoundServer('Close');
    end
    function finishEphys(ephysEnabled)
        if ~ephysEnabled,return;end
        SpikeGLXControl('shutdown');
        recordingState=spikeglx_client('shutdown');
        BpodSystem.Data.EphysActionLog=recordingState.actionLog;
        BpodSystem.Data.EphysShutdownError=recordingState.lastError;
        if ~isempty(recordingState.lastError)
            warning('chipmunk_solo:EphysShutdown','%s',recordingState.lastError);
        end
        % Persist shutdown diagnostics after the behavioral checkpoint is already safe.
        if ~isempty(BpodSystem.Path.CurrentDataFile)
            try
                SessionData=BpodSystem.Data;
                save(BpodSystem.Path.CurrentDataFile{1},'SessionData');
            catch ME
                warning('chipmunk_solo:ShutdownSave','Could not save ephys shutdown diagnostics: %s',ME.message);
            end
        end
    end

end

function [visualIsiList, auditoryIsiList] = assignModalityIsi(modality, isiList, syncMode, offsetFirst, freshList)
% Shared visual/auditory assignment. offsetFirst is 0 for a Poisson train.
% freshList runs only for a non-informative visual train (syncMode == 2).
if modality == 1
    visualIsiList = isiList;
    auditoryIsiList = NaN;
elseif modality == 2
    auditoryIsiList = isiList;
    visualIsiList = isiList;
elseif modality == 3
    auditoryIsiList = isiList;
    if syncMode == 1
        visualIsiList = isiList;
    elseif syncMode == 0
        visualIsiList = isiList(randperm(length(isiList)));
        if offsetFirst
            visualIsiList(1) = visualIsiList(1) + offsetFirst;
        end
    elseif syncMode == 2
        visualIsiList = freshList();
        if offsetFirst
            visualIsiList(1) = visualIsiList(1) + offsetFirst;
        end
    end
end
end
