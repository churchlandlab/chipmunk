%**************************************************************************




%**************************************************************************
function chipmunk

global BpodSystem

%Add the path to the external functions for chipmunk
addpath(genpath(fullfile(BpodSystem.Path.ProtocolFolder,'chipmunk','Functions')));
warning('off','all') %Switch off unnecessary warnings

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

if isfield(BpodSystem.ProtocolSettings,'obsID') %If there is an observer it ill be the main subject and the videos will be saved to its folder
[subjectFolder,bhvFile,~] = fileparts(BpodSystem.Path.CurrentDataFile{2});
else
[subjectFolder,bhvFile,~] = fileparts(BpodSystem.Path.CurrentDataFile{1});
end

%--------------------------------------------------------------------------
%% Start labcams
% if there is a labcam address field and it is not empty start labcams
if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
    %%if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
    try %could be assigned but if no camera available it will throw an error
        tmp = strsplit(BpodSystem.ProtocolSettings.labcamsAddress,':');
        udpAddress = tmp{1};
        udpPort = str2num(tmp{2});
        udpObj = udp(udpAddress,udpPort);
        fopen(udpObj);
        %check if labcams is connected already.
        fwrite(udpObj,'ping');
        if udpObj.BytesAvailable
            fgetl(udpObj);
            disp(' -> labcams connected.');
        else
            %
            disp(' -> starting labcams');
            labcamsproc=System.Diagnostics.Process.Start('labcams.exe',['-w -c ' BpodSystem.ProtocolSettings.cameraSelection]);
            while true
                fwrite(udpObj,'ping')
                tmp = fgetl(udpObj);
                if labcamsproc.HasExited
                    break
                end
                if ~isempty(tmp)
                    break
                end
            end

            videoDataPath = subjectFolder;
%[~,bhvFile,~] = fileparts(BpodSystem.Path.CurrentDataFile{1});
            fwrite(udpObj,['expname=' videoDataPath filesep bhvFile])
            fgetl(udpObj);
            fwrite(udpObj,'manualsave=0')
            fgetl(udpObj);
            fwrite(udpObj,'softtrigger=1')
            fgetl(udpObj);
        end
    catch
        warning('on') %Enable the display of essential warning messages
        warning('A problem occurred with labcams, no video will be recorded')
        warning('off','all')
    end
end

%--------------------------------------------------------------------------
%% Get the polynomial coefficients of the sound calibration
load(fullfile(BpodSystem.Path.LocalDir,'Calibration Files','WhiteNoiseCalibration.mat')) %loading from external calibration file
S.soundCalibrationModelParams = polyfit(reshape(TargetSPLs,1,[]),reshape(10*log10(NoiseAmplitudes),1,[]),1);
%The dirty workaround here
%load('C:\Users\Lukas Oesch\Documents\MATLAB\Bpod Local\Data\FakeSubject\chipmunk\Session Settings\TaskTest.mat','standardSettings');
%S.soundCalibrationModelParams = standardSettings.WhiteNoiseLinearModelParams;

%--------------------------------------------------------------------------
%% Task control sounds and static task parameters
% Set up the task cue sounds and parameters that don't usually change unless
% the user updates them via the the GUI.

% Generate the sounds that signal task-related information and upload them
% to the soundcard (not the stimuli though). In this implementation the
% trial start cue and the go cue after fixation are generated at the same
% loudness (S.goCueLoudness).
generateTaskControlSounds(S.goCueLoudness, S.earlyPunishLoudness, S.earlyPunishTimeout,...
    S.wrongPunishLoudness, S.wrongPunishTimeout, S.soundCalibrationModelParams)

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
if isfield(S, 'obsID')
    BpodSystem.Data.ObsOutcomeRecord = NaN;
    BpodSystem.Data.ObsCompletedTrials = 0;
    BpodSystem.Data.ObsEarlyWithdrawal = 0;
    BpodSystem.Data.ObsDidNotHarvest = 0;
    BpodSystem.Data.ObsRewardAmount = 0;
end
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

%Check whether an observer figure is required
if isfield(S, 'obsID')
    %Set up the observer display
    ObserverFigure('init');
    
    %Initialize the plots on the observer figure
    InterTrialIntervalPlotObserver(BpodSystem.GUIHandles.InterTrialIntervalPlotObserver,'init');
    WaitTimePlotObserver(BpodSystem.GUIHandles.WaitTimePlotObserver, 'init', outcomePlotLimits);
    %Make sure to have run OutcomePlotDemonstrator first to get the display
    %limits!
end

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
if exist('udpObj','var')
    fwrite(udpObj,'softtrigger=0')
    fgetl(udpObj);
    fwrite(udpObj,'manualsave=1')
    fgetl(udpObj);
    fwrite(udpObj,'softtrigger=1')
    fgetl(udpObj);
end

%--------------------------------------------------------------------------
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%------------------------MAIN LOOP-----------------------------------------
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
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
            
            %Re-compute the the task sounds when updating. This is the only
            %static element that can be user-modified.
            generateTaskControlSounds(S.goCueLoudness, S.earlyPunishLoudness, S.earlyPunishTimeout,...
                S.wrongPunishLoudness, S.wrongPunishTimeout, S.soundCalibrationModelParams)
            
            update = 0; %Finish updating
        end
        
        %Refresh the display of controlable parameters that are automatically
        %updated, for example the minWaitTime. Again, make sure to have the
        %observer if there is an observer.
        DemonstratorFigure('refresh', S); %Do this only after updating the user input to  avoid overriding it!
        if isfield(S, 'obsID')
            ObserverFigure('refresh'); %Refresh the display of the trial outcomes 
        end
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
        if S.antiBiasStrength > 0 && prevPropLeft ~= S.propLeft
            if S.antiBiasStrength > 1 %Input check - is this really necessary?
                S.antiBiasStrength = 1; %Limit the antiBias strength
            elseif S.antiBiasStrength < 0
                S.antiBiasStrength = 0; %Limit the antiBias strength
            end
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
        
        %--------The case for the poisson stimulus train---
        if BpodSystem.ProtocolSettings.isPoissonStim
            %Generate a poisson stimulus train by discretizing the stimulus duration
            %into a set of bins, whose duration is the sum of the tone/flash duration
            %and the minimum interval between each stimulus and then randomly
            %assigning tone-interval pairs to the bins
            
            %Specify the minimum interval between individual stimuli
            minInterval = 0.025;   % in s
            
            %Get the stimulus train
            interStimulusIntervalList = poissonStimulusTrain(stimTrainDuration, stimulusDuration, minInterval, stimulusRate);
            
            if ModalityRecord(currentTrial) == 1
                visualIsiList = interStimulusIntervalList;
                auditoryIsiList = NaN;
            elseif ModalityRecord(currentTrial) == 2
                auditoryIsiList = interStimulusIntervalList;
                visualIsiList = interStimulusIntervalList;
            end
            
            %If this is a multi-sensory trial see whether the
            %frequencies are to be presented in sync, randomly shuffled or whether
            %one modality should be non-inforamtive (on the category boundary).
            if ModalityRecord(currentTrial) == 3 %This is multi-sensory
                if BpodSystem.ProtocolSettings.syncMultiSensory == 1 %Synchronized: Visual and auditory stimuli are presented at the same time
                    auditoryIsiList = interStimulusIntervalList;
                    visualIsiList = interStimulusIntervalList;
                    
                elseif BpodSystem.ProtocolSettings.syncMultiSensory == 0 %Asynchronous: the exisiting trial list is reshuffled
                    auditoryIsiList = interStimulusIntervalList;
                    visualIsiList = interStimulusIntervalList(randperm(length(interStimulusIntervalList)));
                    
                elseif BpodSystem.ProtocolSettings.syncMultiSensory == 2 %Visual non-informative: the auditory modality carries information only
                    auditoryIsiList = interStimulusIntervalList;
                    visualIsiList = poissonStimulusTrain(stimTrainDuration, stimulusDuration, minInterval, stimulusRate);
                end
            end
            
        %-----The case for the two-interval rate task-----
        elseif ~BpodSystem.ProtocolSettings.isPoissonStim
            %Generate a stimulus train composed of two different intervals between
            %the individual stimuli.
            
            %Input check -> only a certain range of frequencies can be used for this
            %task version
            if stimulusRate > 16
                stimulusRate = 16;
            end
            if stimulusRate < 9
                stimulusRate = 9;
            end
            
            %Specify the two intervals
            shortInterval = 0.05; %Inter tone/flash interval for high-frequency stimuli (16 Hz) in s
            longInterval = 0.1; %Inter tone/flash interval for low-frequency stimuli (9 Hz) in s
            
            %Get a list of inter-stimulus-intervals forming
            interStimulusIntervalList = twoIntervalStimulusTrain(stimulusRate,shortInterval, longInterval, stimulusDuration, stimTrainDuration);
            
            if ModalityRecord(currentTrial) == 1
                visualIsiList = interStimulusIntervalList;
                auditoryIsiList = NaN;
            elseif ModalityRecord(currentTrial) == 2
                auditoryIsiList = interStimulusIntervalList;
                visualIsiList = interStimulusIntervalList;
            end
            %If this is a multi-sensory trial see whether the
            %frequencies are to be presented in sync, randomly shuffled or whether
            %one modality should be non-inforamtive (on the category boundary).
            if ModalityRecord(currentTrial) == 3 %This is multi-sensory
                if BpodSystem.ProtocolSettings.syncMultiSensory == 1 %Synchronized: Visual and auditory stimuli are presented at the same time
                    auditoryIsiList = interStimulusIntervalList;
                    visualIsiList = interStimulusIntervalList;
                    
                elseif BpodSystem.ProtocolSettings.syncMultiSensory == 0 %Asynchronous: the exisiting trial list is reshuffled
                    auditoryIsiList = interStimulusIntervalList;
                    visualIsiList = interStimulusIntervalList(randperm(length(interStimulusIntervalList)));
                    offsetStimModalities = 0.02; %Introduce a slight offset to ensure no overlap between the modalitties
                    visualIsiList(1) = visualIsiList(1) + offsetStimModalities; %Add the shift to the first zero-interval
                    %CAUTION: By adding the offset one can end up with stimulus
                    %trains that are longer than 1 s!
                    
                elseif BpodSystem.ProtocolSettings.syncMultiSensory == 2 %Visual "non-informative": the auditory modality carries information only
                    %CAUTION: This was changed by LO such that the visual stimuli are
                    %always next to the category boundary!
                    auditoryIsiList = interStimulusIntervalList;
                    
                    visualStimFreq = categoryBoundary-0.5 + round(rand); %Takes values of 12 or 13
                    visualIsiList = twoIntervalStimulusTrain(visualStimFreq,shortInterval, longInterval, stimulusDuration, stimTrainDuration);
                    offsetStimModalities = 0.02; %Introduce a slight offset to ensure no overlap between the modalitties
                    visualIsiList(1) = visualIsiList(1) + offsetStimModalities; %Add the shift to the first zero-interval
                    %CAUTION: By adding the offset one can end up with stimulus
                    %trains that are longer than 1 s!
                end
            end
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
        
        SendStateMatrix(sma); %Send to Bpod
        
        %------------------------------------------------------------------
         %% Display preparation time
        
        % After all is prepared check the time to prepare
        if currentTrial > 1 %Only display updating time from the second trial on
            display(sprintf('Time to retrieve data, update plots and prepare trial number %d: %d seconds',round(currentTrial),toc(preparationTime)));
            display(sprintf('----------------------------------------------------------------------------\n'));
        end
        
        %--------------------------------------------------------------------------
        %% Add to the camera log and run the state machine
        if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
            if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
                fwrite(udpObj,sprintf('log=trial_start: %d',currentTrial))
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
            warning('on')
            warning('There were no events recorded for this trial!')
            warning('off','all')
            end
        end
        
        %--------------------------------------------------------------------------
        %% Write the trial end to the labcams camlog
        
        %The log file is so nice, thx João!
        if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
            if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
                fwrite(udpObj,sprintf('log=trial_end:%d',currentTrial))
            end
        end
        
        %------------------------------------------------------------------
%% Check on Bpod status and save and close if not used anymore

if BpodSystem.Status.BeingUsed == 0
    % Close video object
    if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
        if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
            fwrite(udpObj,sprintf('log=end'));fgetl(udpObj);
            fwrite(udpObj,sprintf('softtrigger=0'));fgetl(udpObj);
            fwrite(udpObj,sprintf('manualsave=0'));fgetl(udpObj);
            fwrite(udpObj,sprintf('quit=1'));
            fclose(udpObj);
            clear udpObj
        end
    end
    SessionData = BpodSystem.Data;
    if ~strcmpi(BpodSystem.ProtocolSettings.demonID,'Virtual') %This is when an observer is exposed to the empty cage
        save(BpodSystem.Path.CurrentDataFile{1},'SessionData') %The file path for the demonstrator is always generated and is in position 1
    end
    
    if isfield(BpodSystem.ProtocolSettings,'obsID')
        save(BpodSystem.Path.CurrentDataFile{2},'SessionData') %If there is an observer, save to her/his folder as well wit hthe .obsmat suffix
    end
    PsychToolboxSoundServer('Close');
    
    if pacedFlag
        LEDswitch()%switch off at the end
    end
    
        %Now copy the saved file over to the server
    if ~isempty(BpodSystem.ProtocolSettings.serverPath) %Only copy to a server when one is specified
        if ~(strcmp(BpodSystem.ProtocolSettings.demonID,'FakeSubject') || strcmp(BpodSystem.ProtocolSettings.demonID,'Virtual'))
            %Do not copy fake subject or virtual (no demonstrator present)
            if ~isfolder(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID))
                mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID))
            end
            splitPath = strsplit(BpodSystem.Path.CurrentDataFile{1},filesep);
            mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID,splitPath{end-2})) % Create a folder for the session date and time
            
            sourceFolder = fileparts(BpodSystem.Path.CurrentDataFile{1});    
            [copyStatus(1), copyErrorMsg{1}] = copyfile(sourceFolder, fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID,splitPath{end-2},splitPath{end-1}),'f');
            %Now copy the entire chipunk folder into the created server
            %folders
        end
        
        if isfield(BpodSystem.ProtocolSettings, 'obsID') %Check whether there is an observer
            if ~isempty(BpodSystem.ProtocolSettings.obsID) && ~(strcmp(BpodSystem.ProtocolSettings.obsID,'FakeSubject'))  %See whether it is our fake subject
                if ~isfolder(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID))
                     mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID))
                end
                splitPath = strsplit(BpodSystem.Path.CurrentDataFile{2},filesep);
                mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID,splitPath{end-2}))% Create a folder for the session date and time
                
                sourceFolder = fileparts(BpodSystem.Path.CurrentDataFile{2});
            [copyStatus(1), copyErrorMsg{1}] = copyfile(sourceFolder, fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID,splitPath{end-2},splitPath{end-1}),'f');
            %Now copy the entire chipunk folder into the created server
            %folders
            end
        end
        
        if exist('copyStatus') % In case the session features no observer and the demonstrator is FakeSubject
            if sum(copyStatus) == 0 %Check for errors
                warning('on')
                warning(sprintf('%s\n',copyErrorMsg{:}))
                warning('off','all')
            end
        end
    end

    clear BpodSystem.GUIHandles.ParamEdit
    display('*********************************************************************')
    display('chipmunk ended')
    return;
end

    %----------------------------------------------------------------------
    %% Update wait time and bias arrays according to
    %  the outcome of the trial that was just completed.
    
    % If previous trial was not an early withdrawal, increase wait duration
    if strcmpi(S.minWaitTime,'Exp') %There are no more wait time steps once the exponential delay mode has been reached.
       S.minWaitTimeStep = 0;
    elseif S.minWaitTime >=1.1
        S.minWaitTimeStep = 0;
        S.minWaitTime = 1.1;
    else %Increase the wait times only when the mouse has been waiting successfully
        if BpodSystem.Data.OutcomeRecord(TrialsDone) > -1 % If the last trial was initiated and the animal waited long enough
            S.minWaitTime = S.minWaitTime + S.minWaitTimeStep;
        end
    end
    
    if isfield(BpodSystem.ProtocolSettings, 'obsID') %Increase the wait time for the observer
        if S.minObsTimeStep > 0
            if S.minObsTime >= S.simulatedMedianDemonTrialDur
                S.minObsTimeStep = 0;
            else
                S.minObsTime = S.minObsTime + S.minObsTimeStep;
            end
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

    
   if isfield(BpodSystem.ProtocolSettings,'obsID')
    InterTrialIntervalPlotObserver(BpodSystem.GUIHandles.InterTrialIntervalPlotObserver,'refresh');
    WaitTimePlotObserver(BpodSystem.GUIHandles.WaitTimePlotObserver, 'refresh', outcomePlotLimits);
   end
   
   %-----------------------------------------------------------------------
   %% Make sure to keep the data if an error occurs
   catch ME
       warning('on')
       warning('chipmunk encounered an error and will save the data and end...')
       warning('off','all')
    % Close video object
    if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
        if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
            fwrite(udpObj,sprintf('log=end'));fgetl(udpObj);
            fwrite(udpObj,sprintf('softtrigger=0'));fgetl(udpObj);
            fwrite(udpObj,sprintf('manualsave=0'));fgetl(udpObj);
            fwrite(udpObj,sprintf('quit=1'));
            fclose(udpObj);
            clear udpObj
        end
    end
    SessionData = BpodSystem.Data;
    if ~strcmpi(BpodSystem.ProtocolSettings.demonID,'Virtual') %This is when an observer is exposed to the empty cage
        save(BpodSystem.Path.CurrentDataFile{1},'SessionData') %The file path for the demonstrator is always generated and is in position 1
    end
    
    if isfield(BpodSystem.ProtocolSettings,'obsID')
        save(BpodSystem.Path.CurrentDataFile{2},'SessionData') %If there is an observer, save to her/his folder as well wit hthe .obsmat suffix
    end
    PsychToolboxSoundServer('Close');
    
    if pacedFlag
        LEDswitch()%switch off at the end
    end
    %Now copy the saved file over to the server
    if ~isempty(BpodSystem.ProtocolSettings.serverPath) %Only copy to a server when one is specified
        if ~(strcmp(BpodSystem.ProtocolSettings.demonID,'FakeSubject') || strcmp(BpodSystem.ProtocolSettings.demonID,'Virtual'))
            %Do not copy fake subject or virtual (no demonstrator present)
            if ~isfolder(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID))
                mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID))
            end
            splitPath = strsplit(BpodSystem.Path.CurrentDataFile{1},filesep);
            mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID,splitPath{end-2})) % Create a folder for the session date and time
            
            sourceFolder = fileparts(BpodSystem.Path.CurrentDataFile{1});
            [copyStatus(1), copyErrorMsg{1}] = copyfile(sourceFolder, fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.demonID,splitPath{end-2},splitPath{end-1}),'f');
            %Now copy the entire chipunk folder into the created server
            %folders
        end
        
        if isfield(BpodSystem.ProtocolSettings, 'obsID') %Check whether there is an observer
            if ~isempty(BpodSystem.ProtocolSettings.obsID) && ~(strcmp(BpodSystem.ProtocolSettings.obsID,'FakeSubject'))  %See whether it is our fake subject
                if ~isfolder(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID))
                     mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID))
                end
                splitPath = strsplit(BpodSystem.Path.CurrentDataFile{2},filesep);
                mkdir(fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID,splitPath{end-2}))% Create a folder for the session date and time
                
                sourceFolder = fileparts(BpodSystem.Path.CurrentDataFile{2});
            [copyStatus(1), copyErrorMsg{1}] = copyfile(sourceFolder, fullfile(BpodSystem.ProtocolSettings.serverPath,BpodSystem.ProtocolSettings.obsID,splitPath{end-2},splitPath{end-1}),'f');
            %Now copy the entire chipunk folder into the created server
            %folders
            end
        end
        
        if exist('copyStatus')
            if sum(copyStatus) == 0 %Check for errors
                warning('on')
                warning(sprintf('%s\n',copyErrorMsg{:}))
                warning('off','all')
            end
        end
    end
    BpodSystem.Status.BeingUsed = 0; %Switch the Bpod off
    clear BpodSystem.GUIHandles.ParamEdit
    display('*********************************************************************')
    display('chipmunk ended due to an error, see below') %Inform the user
    rethrow(ME) %Display the error message
end
end


