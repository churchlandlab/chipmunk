function half_second_chipmunk_solo

global BpodSystem

%Add the path to the external functions for chipmunk
addpath(genpath(fullfile(BpodSystem.Path.ProtocolFolder,'half_second_chipmunk_solo','Functions')));

%% Initialize the protocol
%Load the settings for the respective experiment and start the protocol
S = initChipmunk;

%--------------------------------------------------------------------------
%% Decide on the sound handling

%Find sound card for stimuli
PsychToolboxSoundServer('init'); % Try and let this crash before all the other inputs are passed

%Set soft code handler to trigger sounds
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';

SamplingFreq = 192000; %The frequency of the (Fenix) sound card

[subjectFolder,bhvFile,~] = fileparts(BpodSystem.Path.CurrentDataFile{1});

%--------------------------------------------------------------------------
%% Start labcams
%if there is a labcam address field and it is not empty start labcams

if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
    %%if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
    try %could be assigned but if no camera available it will throw an error
        tmp = strsplit(BpodSystem.ProtocolSettings.labcamsAddress,':');
        udpAddress = tmp{1};
        udpPort = str2num(tmp{2});
        udplabcams = udp(udpAddress,udpPort);
        fopen(udplabcams);
        %check if labcams is connected already.
        fwrite(udplabcams,'ping');
        if udplabcams.BytesAvailable
            fgetl(udplabcams);
            disp(' -> labcams connected.');
        else
            disp(' -> starting labcams');
            system('export LD_LIBRARY_PATH=""; export QT_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/qt5/plugins/platforms/; gnome-terminal -- labcams -w')
                    for i =  1:5
                        fwrite(udplabcams,'ping')
                        tmp = fgetl(udplabcams);
                        pause(0.1)
                        if ~isempty(tmp)
                            break
                        end
                    end
                    if isempty(tmp)
                        clear udplabcams
                    end
            if exist('udplabcams', 'var')
                videoDataPath = subjectFolder;
                fwrite(udplabcams,['expname=' videoDataPath filesep bhvFile])
                fwrite(udplabcams,'load_reference=/home/anne/reference_image')
                fgetl(udplabcams);
                fwrite(udplabcams,'manualsave=0')
                fgetl(udplabcams);
                fwrite(udplabcams,'softtrigger=1') %change this to 0 for ephys recordings
                fgetl(udplabcams);
            end
        end
    catch
        warning('A problem occurred with labcams, no video will be recorded')
    end
end


%--------------------------------------------------------------------------
%% Send animal and session info to the miniscope computer
if ~isempty(BpodSystem.ProtocolSettings.miniscopeID) %Enforce that the user provides a name to
    %miniscope that will be used.
    if ~isempty(BpodSystem.ProtocolSettings.miniscopeAddress)
        tmp = strsplit(BpodSystem.ProtocolSettings.miniscopeAddress,':'); %Retrieve the miniscope computer's name and port number
        miniscopeServerName = tmp{1};
        miniscopeServerPort = str2num(tmp{2});

        miniscopeConnection = udp(miniscopeServerName, miniscopeServerPort); %Establish connection and open to write and read
        fopen(miniscopeConnection);

        tmp = strsplit(subjectFolder, filesep);
        %Here the info of the folder structure can be used. The second last
        %layer is the session (tmp{end-1}) and the third last layer the animal ID (tmp{end-2}) .

        messageSent = [tmp{end-2} ',' tmp{end-1}, ',' BpodSystem.ProtocolSettings.miniscopeID];
        fwrite(miniscopeConnection, messageSent);
        %Send info separated by comma

        acknowledgement = []; %Store the message returned from server
        waitForServer = tic;
        while isempty(acknowledgement) %Stop when a message arrives or latest after 5 s.
            acknowledgement = fread(miniscopeConnection, length(messageSent));
            if toc(waitForServer) > 5 %For some reason this can not be inside the while conditions...
                break
            end
        end
        messageReturned = string(native2unicode(acknowledgement')); %Flip this first to get a regular string back
        if strcmp(messageReturned, messageSent) %Check whether the server understood correctly, throw error and return otherwise.
            disp('Successfully sent session information to miniscope computer!')
        else
            if strcmp(messageReturned,"") %See whether the acknowledgment is empty
                error('The connection attempt to the miniscope computer has timed-out\nMake sure to execute syncMiniscopeToBpod.py and check connection.')
            else
                error('Information was not accurately transmitted to the miniscope computer. The server echoed the following message:\n%s', messageReturned)
            end
        end
        fclose(miniscopeConnection); %Just to keep it clean.
    end
end

%--------------------------------------------------------------------------
%% Get the polynomial coefficients of the sound calibration
load(fullfile(BpodSystem.Path.LocalDir,'Calibration Files','WhiteNoiseCalibration.mat')) %loading from external calibration file
S.soundCalibrationModelParams = polyfit(reshape(TargetSPLs,1,[]),reshape(10*log10(NoiseAmplitudes),1,[]),1);

%--------------------------------------------------------------------------
%% Task control sounds and static task parameters
% Set up the task cue sounds and parameters that don't usually change unless
% the user updates them via the the GUI.

% Generate the sounds that signal task-related information and upload them
% to the soundcard (not the stimuli though). In this implementation the
% trial start cue and the go cue after fixation are generated at the same
% loudness (S.goCueLoudness).

% Fixed stimulus properties that remain unchanged
stimTrainDuration = 1;

%--------------------------------------------------------------------------
%% Randomly draw trial sides and pre-assign bias arrays
%Generate a random list of trial sides based on the porportion of left
%choices in the settings.
maxTrialNum = 5000; %Constrain the number of trials but at rather high value
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

%--------------------------------------------------------------------------
%% Dummy state matrix
% Initialize the state matrix associated with this experiment for the
% display on the plot. If no additional
[sma, ~, reviseChoiceFlag, pacedFlag] = eval([BpodSystem.ProtocolSettings.smaAssembler '();']);

%--------------------------------------------------------------------------
% % %% Initialize variables used for display. These variables
% % OutcomeRecord = nan(1,maxTrialNum);
ModalityRecord = nan(1,maxTrialNum);

%--------------------------------------------------------------------------
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
%--------------------------------------------------------------------------
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
%--------------------------------------------------------------------------
%% Prepare the trial loop

TrialsDone =  0; %This is the number of already finished trials and is by definition currentTrial-1
global update
update = 1; %Define the update variable and make sure that we retrieve some changes made at the startup.

if BpodSystem.Status.BeingUsed %only run this code if protocol is still active
    disp('Set the camera and hit start')
    uiwait(BpodSystem.GUIHandles.Figures.DemonFigure); %Wait for the user to click start
else
    return %Peacefully stop execution if the Bpod was switched off up to here.
end

if pacedFlag
    LEDswitch()%When the trials are paced by an observer or virtually  switch on LEDs that indicate no initiation possible
end
%--------------------------------------------------------------------------
%% Start saving labcams if connected
if exist('udplabcams','var')
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

%--------------------------------------------------------------------------
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%------------------------MAIN LOOP-----------------------------------------
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
tstart = tic;
for currentTrial = 1:maxTrialNum
    try %This is to make sure that the data will be saved even if some error occurs during its execution
        disp("---------------New Loop Starts!---------------");
        tic
        %% Check for user-inputs and change display of automatically changing
        %parameters on the figures.
        if update == 1 || TrialsDone == 0
            S = DemonstratorFigure('update', S);
            %Updates S and BpodSystem.ProtocolSettings with the input from the
            %user. When an observer is present the observer figure needs to
            %have been initialized and it needs to exist. Otherwise the content
            %of the UIcontrols cannot be evaluated.

            update = 0; %Finish updating
        end

        %Refresh the display of controlable parameters that are automatically
        %updated, for example the minWaitTime. Again, make sure to have the
        %observer if there is an observer.
        DemonstratorFigure('refresh', S); %Do this only after updating the user input to  avoid overriding it!
        %----------------------------------------------------------------------
        %% Randomly select the stimulus modality for the current trial
        ModalityRecord(currentTrial) = drawStimModality;

        %----------------------------------------------------------------------
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

        %--------------------------------------------------------------------------
        %% Find the frequency of the stimulus given the assigned side and modality

        % First define the category boundary for this type of trial
        if BpodSystem.ProtocolSettings.isPoissonStim == 0
            categoryBoundary = 12.5;    %events/s for the two-interval rate task
        else
            categoryBoundary = 12; %For the poisson rate task
        end

        % Find a stimulus rate associated with the designated correct side
        stimulusRate = findStimRate(TrialSidesList(currentTrial), ModalityRecord(currentTrial));

        %--------------------------------------------------------------------------
        %% Generate the stim train according to the chosen frequency and specified task design

        % Specify the duration of the stimulus train and of the individual stimulus
        stimulusDuration = 0.015; %In s
        stimTrainDuration = 1; %In s

        if BpodSystem.ProtocolSettings.isPoissonStim
            minInterval = 0.025;
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
            interStimulusIntervalList = twoIntervalStimulusTrain(stimulusRate, shortInterval, longInterval, stimulusDuration, stimTrainDuration);
            [visualIsiList, auditoryIsiList] = assignModalityIsi(ModalityRecord(currentTrial), interStimulusIntervalList, ...
                BpodSystem.ProtocolSettings.syncMultiSensory, 0.02, ...
                @() twoIntervalStimulusTrain(categoryBoundary-0.5+round(rand), shortInterval, longInterval, stimulusDuration, stimTrainDuration));
        end

        %--------------------------------------------------------------------------
        %% Construct the stim signal and refresh plots

        %Sound parameters
        soundType = 'whiteNoise + envelope';
        addedNoiseLoudness = 10;

        %Assemble the signal
        if ModalityRecord(currentTrial) == 1 %It's a visual trial
            visualStimSignal = createVisualStimSignal(interStimulusIntervalList, SamplingFreq, BpodSystem.ProtocolSettings.stimBrightness, stimulusDuration);
            auditoryStimSignal = zeros(1,length(visualStimSignal)); %Zero-signal
        elseif ModalityRecord(currentTrial) == 2 %It's an auditory trial
            auditoryStimSignal = createAuditoryStimSignal(interStimulusIntervalList, SamplingFreq, stimulusDuration,...
                soundType, BpodSystem.ProtocolSettings.stimLoudness, addedNoiseLoudness, BpodSystem.ProtocolSettings.soundCalibrationModelParams);
            visualStimSignal = zeros(1,length(auditoryStimSignal)); %Zero-signal
        elseif ModalityRecord(currentTrial) == 3
            visualStimSignal = createVisualStimSignal(visualIsiList, SamplingFreq, BpodSystem.ProtocolSettings.stimBrightness, stimulusDuration);
            auditoryStimSignal = createAuditoryStimSignal(auditoryIsiList, SamplingFreq, stimulusDuration,...
                soundType, BpodSystem.ProtocolSettings.stimLoudness, addedNoiseLoudness, BpodSystem.ProtocolSettings.soundCalibrationModelParams);
        end

        %Refresh the stimulus train plots
        StimulusPlotDemonstrator(BpodSystem.GUIHandles.StimulusPlotV, BpodSystem.GUIHandles.StimulusPlotA, 'refresh', [visualStimSignal; auditoryStimSignal]);

        %--------------------------------------------------------------------------
        %% Repeat parts of the signal for an extended amount of time and upload
        %  the stimuli once finished

        stimTrainSignals =  [visualStimSignal; auditoryStimSignal]; %Concatenate here for easier treatment
        if BpodSystem.ProtocolSettings.extraStimDur > 1/SamplingFreq %Only if we can actually add something
            prolongedStimTrain = repmat(stimTrainSignals,[1,ceil(BpodSystem.ProtocolSettings.extraStimDur/stimTrainDuration)]); %make enough copies of the stimulus train
            stimTrainSignals = [stimTrainSignals prolongedStimTrain(:,1:BpodSystem.ProtocolSettings.extraStimDur*SamplingFreq)]; %Pick the necessary length of extra signal
        end

        PsychToolboxSoundServer('Load', 1, stimTrainSignals); %Upload the signal

        %--------------------------------------------------------------------------
        %% Assemble and the state matrix for the trial

        [sma, trialDelays, reviseChoiceFlag, pacedFlag]  = eval([BpodSystem.ProtocolSettings.smaAssembler '(' sprintf('%d',TrialSidesList(currentTrial)) ');']);
        % Get the state matrix, the random delays generated inside the assembler
        % function and a logical value that indicates whether the animals can revise
        % wrong choices and whether trials are self-initiated.
        %For more info check the respective SMA function.

        generateTaskControlSounds(S.goCueLoudness, S.earlyPunishLoudness, S.earlyPunishTimeout,...
            S.wrongPunishLoudness, S.wrongPunishTimeout, S.soundCalibrationModelParams, trialDelays)

        SendStateMatrix(sma); %Send to Bpod

        %------------------------------------------------------------------
        %% Display preparation time

        % After all is prepared check the time to prepare
        if currentTrial > 1 %Only display updating time from the second trial on
            fprintf('Time to retrieve data, update plots and prepare trial number %d: %d seconds\n',round(currentTrial),toc(preparationTime));
            fprintf('----------------------------------------------------------------------------\n\n');
        end

        %--------------------------------------------------------------------------
        %% Add to the camera log and run the state machine
        if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
            if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
                
                fwrite(udplabcams,sprintf('log=trial_start[%4.0f]: %d',toc(tstart)/60,currentTrial))
            end
        end

        if pacedFlag
            LEDswitch() %Switch off and let the state control LEDs
        end

        RawEvents = RunStateMatrix; %Finally run the state matrix

        if pacedFlag
            LEDswitch() %Make sure to switch the LEDs on again if the trials are paced!
        end
        %--------------------------------------------------------------------------
        %% Retrieve the trial information to save it

        preparationTime = tic; %Start measuring the time to extract, save and prepare
        TrialsDone = TrialsDone + 1; %increment number of trials done

        % Retrieving data
        if ~isempty(fieldnames(RawEvents))
            %Incorporate trial and outcome information into the Data field inside
            %BpodSystem.
            retrieveTrialData(RawEvents,TrialsDone,TrialSidesList,trialDelays,reviseChoiceFlag, ModalityRecord,...
                stimulusDuration, stimTrainDuration, categoryBoundary,interStimulusIntervalList,visualIsiList,auditoryIsiList);
        else
            if BpodSystem.Status.BeingUsed == 1 %Do not show this warning if the session is ending
                warning('There were no events recorded for this trial!')
            end
        end

        BpodSystem.Data = BpodNotebook('sync', BpodSystem.Data); %Store the notes with the session data
        %--------------------------------------------------------------------------
        %% Write the trial end to the labcams camlog

        %The log file is so nice, thx João!
        if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
            if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
                fwrite(udplabcams,sprintf('log=trial_end:%d',currentTrial))
            end
        end

        %------------------------------------------------------------------
        %% Check on Bpod status and save and close if not used anymore

        if BpodSystem.Status.BeingUsed == 0
            shutdownChipmunk();
            disp('*********************************************************************')
            return;
        end

        %----------------------------------------------------------------------
        %% Update wait time and bias arrays according to
        %  the outcome of the trial that was just completed.

        % If previous trial was not an early withdrawal, increase wait duration
        if strcmpi(S.minWaitTime,'Exp') %There are no more wait time steps once the exponential delay mode has been reached.
            S.minWaitTimeStep = 0;
        elseif S.minWaitTime >=0.6
            S.minWaitTimeStep = 0;
            S.minWaitTime = 0.6;
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

        %-----------------------------------------------------------------------
        %% Update the performance plots

        outcomePlotLimits = OutcomePlotDemonstrator(BpodSystem.GUIHandles.OutcomePlotDemonstrator, 'refresh',currentTrial+1,TrialSidesList,BpodSystem.Data.OutcomeRecord);
        PerformancePlotDemonstrator(BpodSystem.GUIHandles.PerformancePlotDemonstrator,'refresh',outcomePlotLimits);
        PsychometricPlotDemonstrator(BpodSystem.GUIHandles.PsychometricPlotDemonstrator,'refresh');
        WaitTimeDiffPlotDemonstrator(BpodSystem.GUIHandles.WaitTimeDiffPlotDemonstrator,'refresh',true);

        %-----------------------------------------------------------------------
        %% Make sure to keep the data if an error occurs
    catch ME
        warning('half_second_chipmunk_solo encountered an error and will save the data and end...')
        BpodSystem.Status.BeingUsed = 0;
        shutdownChipmunk();
        disp('*********************************************************************')
        disp('chipmunk ended due to an error, see below')
        rethrow(ME)
    end
end

    function shutdownChipmunk()
        % ponytail: one shutdown for the stop button and for errors.
        global BpodSystem
        if isfield(BpodSystem.ProtocolSettings,'labcamsAddress') && ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
            fwrite(udplabcams,sprintf('log=end')); fgetl(udplabcams);
            fwrite(udplabcams,sprintf('softtrigger=0')); fgetl(udplabcams);
            fwrite(udplabcams,sprintf('manualsave=0')); fgetl(udplabcams);
            pause(1)
            fwrite(udplabcams,sprintf('quit=1'));
            fclose(udplabcams);
        end
        SessionData = BpodSystem.Data;
        if ~strcmpi(BpodSystem.ProtocolSettings.demonID,'Virtual')
            save(BpodSystem.Path.CurrentDataFile{1},'SessionData')
            trializedNoteIdx = [];
            for noteIdx = 1:length(BpodSystem.Data.Notes)
                if ~isempty(BpodSystem.Data.Notes{noteIdx})
                    trializedNoteIdx(end+1) = noteIdx;
                end
            end
            if ~isempty(trializedNoteIdx)
                notesFile = fopen(fullfile(fileparts(BpodSystem.Path.CurrentDataFile{1}), 'notes.txt'), 'w');
                for noteIdx = 1:length(trializedNoteIdx)
                    fprintf(notesFile, [sprintf('Trial %d: ', round(trializedNoteIdx(noteIdx))) BpodSystem.Data.Notes{trializedNoteIdx(noteIdx)} '\n']);
                end
                fclose(notesFile);
            end
        end
        PsychToolboxSoundServer('Close');
        if pacedFlag
            LEDswitch()
        end
        if ~(strcmp(BpodSystem.ProtocolSettings.demonID,'FakeSubject') || strcmp(BpodSystem.ProtocolSettings.demonID,'Virtual'))
            fPath = fileparts(BpodSystem.Path.CurrentDataFile{1});
            system(['export LD_LIBRARY_PATH=""; gnome-terminal -- labdata put ', fPath, ' --ask']);
        end
        clear BpodSystem.GUIHandles.ParamEdit
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
