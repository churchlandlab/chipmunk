% My first protocol for Bpod
% David Raposo, Kachi Odoemene Sep 2014
% Based on RateDiscrimination (by Kachi)

% Modification history
% 26-Sep-2014 by KO: Separate rewards for each port
%                    Event rate list
% 10-Oct-2014 by KO: Added Matt Kaufman's antibias code
% 30-Oct-2014 by KO: Changed category boundary to 12 events/s, such that 12
%                    evts/s is randomly rewarded. Changed ">" or "<" before categoryBoundary
%                    to ">=" or "<=" categoryBoundary
% 04-Jan-2015 by KO: Incorporated Matt Kaufman's antibias function
%                    Added option for center port reward
% 14-Jan-2015 by KO: Added functionality to plot psychometric function
%                    Added extra stimulus
% 28-Jan-2015 by KO: Added LED reward port cue
% 11-Dec-2015 by KO: Added auto-run configuration. useful for test recording sessions

function chipmunk

global BpodSystem

% Initialize sound server
PsychToolboxSoundServer('init')
% Set soft code handler to trigger sounds
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';

%Store the data and settings in folders with date spec
allFolders = split(BpodSystem.Path.CurrentDataFile,filesep);
sessionFolder = [];
for k=1:length(allFolders)-2 %also the actual file is a cell!
    sessionFolder = fullfile(sessionFolder, allFolders{k});
end
sessionFolder = fullfile(sessionFolder, char(datetime('today', 'Format','uuuuMMdd')));

%check for existing Session Data directory
if ~isfolder(fullfile(sessionFolder,allFolders{end-1}))
mkdir(sessionFolder,allFolders{end-1});
end
% Same for Session Settings
if ~isfolder(fullfile(sessionFolder,'Session Settings'))
mkdir(sessionFolder,'Session Settings');
end
BpodSystem.Path.CurrentDataFile = fullfile(sessionFolder,allFolders{end-1},allFolders{end});
BpodSystem.Path.CurrentProtocol = fullfile(sessionFolder,allFolders{end-1},allFolders{end});

%% Define settings for protocol

%Initialize default settings.
%Append new settings to the end

% Extract subject name for video from data file name
[~,dataFileName] = fileparts(BpodSystem.Path.CurrentDataFile);
underlineIndex = strfind(dataFileName, '_');
DefaultSettings.SubjectName = dataFileName(1:min(underlineIndex)-1);

DefaultSettings.leftRewardVolume = 24; % ul
DefaultSettings.rightRewardVolume = 24;% ul
% DefaultSettings.centerRewardVolume = 0;% ul
% DefaultSettings.centerRewardProp = 0; %probability of center reward
DefaultSettings.highRateSide = 'L';
DefaultSettings.preStimDelayMin = 0.001; % secs
DefaultSettings.preStimDelayMax = 0.1; % secs
DefaultSettings.lambdaDelay = 15;
DefaultSettings.minWaitTime = 0.025; % secs
DefaultSettings.minWaitTimeStep = 0.0005;% secs
DefaultSettings.timeToChoose = 10; % secs
DefaultSettings.timeOut = 0; % secs
DefaultSettings.visEventRateList = [9 16]; %events per second
DefaultSettings.audEventRateList = [9 16]; %events per second
DefaultSettings.multEventRateList = [9 16]; %events per second
DefaultSettings.PropLeft = 0.5;
DefaultSettings.PropOnlyAuditory = 1;
DefaultSettings.PropOnlyVisual = 1;
DefaultSettings.SynchMultiSensory = 1;
DefaultSettings.WaitStartCue = 0;
DefaultSettings.WaitEndGoCue = 1;
DefaultSettings.PlayStimulus = 1;
DefaultSettings.StimBrightness = 20;
% DefaultSettings.PWMBrightness = 0;
DefaultSettings.StimLoudness = 80;
DefaultSettings.GoCueLoudness = 80;
DefaultSettings.Direct = 1; %probability/fraction of trials that are direct reward
DefaultSettings.PortLEDCue = 0; %cue the animal to reward port--28Jan2015
DefaultSettings.AutoRun = 0; %runs in autorun configuration. behavioral reporting not required, trials will be initiated

DefaultSettings.UseAntiBias = 0;
DefaultSettings.AntiBiasTau = 0; %reflects number of trials to look back to compute bias measure.
DefaultSettings.labcamsAddress = '';%'127.0.0.1:9999 for Rig 2';
load('C:\Users\Anne\Dropbox\rat_protocols\Bpod\TheMudSkipper2\WhiteNoiseCalibration.mat');     % Here, the addresses of the same Dropbox file in Ubuntu and Windows
% are different. This will induce bugs if you run this code on a computer with
% Ubuntu. Please make sure the file address you are using is correct.
DefaultSettings.WhiteNoiseLinearModelParams = polyfit(reshape(TargetSPLs,1,[]),reshape(10*log10(NoiseAmplitudes),1,[]),1);
DefaultSettings.ExtraStimDuration = 0; %sec
DefaultSettings.ExtraStimDurationStep = 0; %secs...0.00006 will decrement at approx 200ms /week, 0.00008 ms at ~250ms/week (assuming mouse performs 650 on average every session)
DefaultSettings.PlotPMFnTrials = 100;
DefaultSettings.UpdatePMfnTrials = 5;
DefaultSettings.NumWarmup = 0;
DefaultSettings.PunishLoudness = 70;
DefaultSettings.PunishDuration = 2;
DefaultSettings.EarlyPunishLoudness = 70;
DefaultSettings.EarlyPunishDuration = 2;
DefaultSettings.IsPoissonStim = 0;
DefaultSettings.initCenterPlayStimUntilCorrect = false; %start by poking in center play stimulus until correct or time is up.
DefaultSettings.holdCenterStimUntilCorrect = false;

defaultFieldNames = fieldnames(DefaultSettings);

prevSettings = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct S
prevFieldNames = fieldnames(prevSettings);
prevFieldVals = struct2cell(prevSettings);

newSettings = DefaultSettings;
for n = 1:numel(defaultFieldNames)
    thisfield = defaultFieldNames{n};
    index = find(strcmpi(thisfield,prevFieldNames));
    if isempty(index)
        continue;
    end
    newSettings.(thisfield) = prevFieldVals{index};
end

S = newSettings; %update parameters

% Launch parameter GUI
BpodParameterGUI_Visual('init', S);

% if there is a labcam address field and it is not empty start labcams
if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
    if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
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
            labcamsproc=System.Diagnostics.Process.Start('labcams.exe','-w');
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
%             videoDataPath = fullfile('C:','Users','Anne','Documents','Bpod Local','Data',...
%                 BpodSystem.ProtocolSettings.SubjectName,'chipmunk', datetime('today', 'Format','uuuuMMdd'),'video');
            videoDataPath = fullfile(sessionFolder,'video')
[~,bhvFile,~] = fileparts(BpodSystem.Path.CurrentDataFile);
            fwrite(udpObj,['expname=' videoDataPath filesep bhvFile])
            fgetl(udpObj);
            fwrite(udpObj,'manualsave=0')
            fgetl(udpObj);
            fwrite(udpObj,'softtrigger=1')
            fgetl(udpObj);
        end
    end
end

%%
SamplingFreq = 192000; % This has to match the sampling rate initialized in PsychToolboxSoundServer.m

% Preconfigure audio signals and load to psychtoolbox
generateAndUploadSounds(SamplingFreq, S.StimLoudness, S.GoCueLoudness, S.EarlyPunishLoudness, S.EarlyPunishDuration, S.PunishLoudness, S.PunishDuration, S.WhiteNoiseLinearModelParams);

if S.IsPoissonStim == 0
    categoryBoundary = 12.5; %events/s
else
    categoryBoundary = 12;
end

% ports are numbered 0-7. Need to convert to 8bit values for bpod
LeftPortValveState = 2^0;
CenterPortValveState = 2^1;
RightPortValveState = 2^2;

% Stimulus parameters
% The parameters below are typically not changed from trial to trial, so
% keep fixed for now. Nonetheless, save on each trial

eventDuration = 0.020; % secs
desiredStimDuration =  1; % secs

% Create trial types (left vs right)

%%%%%%%%% Should i change the process of making TrialSidesList
maxTrials = 5000;
coin0 = rand(1,maxTrials);
TrialSidesList = coin0 > (1-S.PropLeft);
TrialSidesList = TrialSidesList(randperm(maxTrials));
PrevPropLeft = S.PropLeft;

% % Antibias parameters
AntiBiasPrevLR =  NaN;
AntiBiasPrevSuccess = NaN;
SuccessArray = 0.5 * ones(2, 2, 2);    % successArray will be: prevTrialLR x prevTrialSuccessful x thisTrialLR
ModalityRightArray = 0.5 * ones(1, 3);

%% Initialize GUI plots
BpodSystem.GUIHandles.Figures.FigureAllFigures = figure('Position', [500 100 650 750], 'name', 'All Plots', 'numbertitle', 'off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.OutcomePlot = axes('Units', 'pixels', 'Position', [70 580 500 100],'tickdir','out');
BpodSystem.GUIHandles.PerformancePlot = axes('Units', 'pixels', 'Position', [70 440 500 100],'tickdir','out');
BpodSystem.GUIHandles.StimulusPlotA = axes('Units', 'pixels', 'Position', [70 380 500 30],'tickdir','out');
BpodSystem.GUIHandles.StimulusPlotV = axes('Units', 'pixels', 'Position', [70 340 500 30],'tickdir','out');
BpodSystem.GUIHandles.PMFPlot = axes('Units', 'pixels', 'Position', [70 30 240 260],'tickdir','out','ytick',(0:0.25:1),'XGrid','on','YGrid','on','YLim',[0 1.05]);
BpodSystem.GUIHandles.PMFPlotData = line([0 0],[0 0],'LineStyle','-','Marker','.','MarkerSize',6');

BpodSystem.GUIHandles.LabelsText.TrialsDone = uicontrol('Style', 'text', 'String', 'Trials Done:', 'Position', [330 290 60 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');
BpodSystem.GUIHandles.LabelsText.CompletedTrials = uicontrol('Style', 'text', 'String', 'Valid Trials:', 'Position', [330 260 60 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');
BpodSystem.GUIHandles.LabelsText.RewardedTrials = uicontrol('Style', 'text', 'String', 'Rewarded Trials:', 'Position', [330 230 85 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');
BpodSystem.GUIHandles.LabelsText.WaterAmount = uicontrol('Style', 'text', 'String', 'Est. Water (mL):', 'Position', [330 200 85 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');
BpodSystem.GUIHandles.LabelsVal.TrialsDone = uicontrol('Style', 'text', 'String', '0', 'Position', [400 290 30 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');
BpodSystem.GUIHandles.LabelsVal.CompletedTrials = uicontrol('Style', 'text', 'String', '0', 'Position', [400 260 30 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');
BpodSystem.GUIHandles.LabelsVal.RewardedTrials = uicontrol('Style', 'text', 'String', '0', 'Position', [420 230 30 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');
BpodSystem.GUIHandles.LabelsVal.WaterAmount = uicontrol('Style', 'text', 'String', '0', 'Position', [420 200 45 18], 'FontWeight', 'normal', 'FontSize', 10, 'FontName', 'Arial');


OutcomePlot(BpodSystem.GUIHandles.OutcomePlot, 'init', TrialSidesList);
PerformancePlot(BpodSystem.GUIHandles.PerformancePlot,'init');

%% Initialize arrays for storing values later
OutcomeRecord = nan(1,maxTrials);
Rewarded = nan(1,maxTrials);
EarlyWithdrawal = nan(1,maxTrials);
DidNotChoose = nan(1,maxTrials);
ResponseSideRecord = nan(1,maxTrials);
modalityRecord = nan(1,maxTrials);
correctSideRecord = nan(1,maxTrials);
RewardAmounts = nan(1,maxTrials);

% In current tasks, center port isn't used for giving reward.
CenterValveTime = 0;
centerRewarded = 0;

TrialsDone =  0;
global update
update = 0;

if BpodSystem.Status.BeingUsed %only run this code if protocol is still active
    % start spout adjustment
    disp('Set the camera and hit start')
    uiwait(BpodSystem.GUIHandles.Figures.FigureAllFigures); %wait for spout control and clear handle afterwards
end
%% Start saving labcams if connected
if exist('udpObj','var')
    fwrite(udpObj,'softtrigger=0')
    fgetl(udpObj);
    fwrite(udpObj,'manualsave=1')
    fgetl(udpObj);
    fwrite(udpObj,'softtrigger=1')
    fgetl(udpObj);
end
%% Main loop
for currentTrial = 1:maxTrials
    disp("---------------New Loop Starts!---------------");
    tic
    if update == 1 || TrialsDone == 0
        S = BpodParameterGUI_Visual('update', S);
        drawnow; % Sync parameters with BpodParameterGUI plugin
        
        % If anything from GUI was changed, then regenerate and re-upload the sounds to the sound server
        generateAndUploadSounds(SamplingFreq, S.StimLoudness, S.GoCueLoudness, S.EarlyPunishLoudness, S.EarlyPunishDuration, S.PunishLoudness, S.PunishDuration, S.WhiteNoiseLinearModelParams);
        LeftRewardVolume = S.leftRewardVolume;
        RightRewardVolume = S.rightRewardVolume;
        audEventRateList = S.audEventRateList;
        visEventRateList = S.visEventRateList;
        multEventRateList = S.multEventRateList;
        
        % First ensure that anti-bias strength is a sane value, between 0 and 1
        if S.UseAntiBias < 0
            S.UseAntiBias = 0;
        elseif S.UseAntiBias > 1
            S.UseAntiBias = 1;
        end
        
        if S.IsPoissonStim == 0
            categoryBoundary = 12.5;    %events/s
        else
            categoryBoundary = 12;
        end
        
        update = 0;
    end
    toc
    
    tic
    disp('Parameter preparation time:');
    % Judge the waittime length is fixed or getting from a exponential distribution
    if isequal(S.minWaitTime,'exp') || isequal(S.minWaitTime,'Exp') || isequal(S.minWaitTime,'exponential')
        S.minWaitTime = WaitTime_Exponential(50, 1000, 10);   % The three parameters here are: minimal delay, maximal delay, stepsize
        WaitTimeMode = 'Exp';
        
    else
        WaitTimeMode = 'Fixed';
    end
    
    LeftValveTime = GetValveTimes(LeftRewardVolume, 1);
    RightValveTime = GetValveTimes(RightRewardVolume, 3);
    
    
    %     if rand < S.centerRewardProp %reward center
    %         CenterValveTime = GetValveTimes(S.centerRewardVolume, 2);
    %         disp('center reward')
    %         centerRewarded = 1;
    %     end
    
    directTrial = rand < S.Direct; %probability of direct reward
    
    if TrialsDone > 1
        outcome  = OutcomeRecord(TrialsDone);
        if outcome > -1
            
            % Update arrays
            [newModalityRightArray, newSuccessArray] = updateAntiBiasArrays(ModalityRightArray, SuccessArray, ...
                modalityRecord(TrialsDone - 1), outcome, ...
                correctSideRecord(TrialsDone -1), ...
                AntiBiasPrevLR, AntiBiasPrevSuccess, ...
                S.AntiBiasTau, ResponseSideRecord(TrialsDone - 1) - 1);
            
            % Update history
            AntiBiasPrevLR = correctSideRecord(TrialsDone -1);
            AntiBiasPrevSuccess = (OutcomeRecord(TrialsDone -1) == 1);
            
            % Update matrices
            SuccessArray= newSuccessArray;
            ModalityRightArray= newModalityRightArray;
            
        end
        
    end %end TrialsDone%
    
    preStimDelay = generate_random_delay(S.lambdaDelay, S.preStimDelayMin, S.preStimDelayMax);
    %         postStimDelay = generate_random_delay(S.lambdaDelay, S.postStimDelayMin, S.postStimDelayMax);
    
    % Determine stimulus modality
    show_audio = 0;
    show_visual = 0;
    coin_modality = rand;
    
    if coin_modality < S.PropOnlyAuditory % only audio
        Modality = 'Auditory';
        disp('Auditory trial');
        show_audio = 1;
        modalityNum = 1;
        
    elseif coin_modality < S.PropOnlyVisual + S.PropOnlyAuditory % only visual
        Modality = 'Visual';
        disp('Visual trial');
        show_visual = 1;
        modalityNum = 2;
        
    else % audio & visual
        Modality = 'Multisensory';
        disp('Multisensory trial');
        show_audio = 1;
        show_visual = 1;
        modalityNum= 3;
        
    end
    
    % Anti-bias for coming trial
    % If we've previously done a trial, are using anti-bias, and the
    % previous trial wasn't an early withdrawal or failure to choose,
    % update the next trial.
    % Note: at this point in the trial, 'outcome' is still from the
    % previous trial
    
    
    if TrialsDone > 1 && S.UseAntiBias > 0 && outcome > -1
        
        pLeft = getAntiBiasPLeft(SuccessArray, ModalityRightArray, modalityNum, ...
            S.UseAntiBias, AntiBiasPrevLR, AntiBiasPrevSuccess);
        
        coin_anitibias = rand(1);
        sidesList = TrialSidesList;
        
        sidesList(currentTrial) = coin_anitibias > (1 - pLeft); %the sign is important, it must match the way left and right trials are assigned based on prop left/right
        TrialSidesList = sidesList; %update trial type list
        
    elseif TrialsDone > 1 && (S.PropLeft ~= PrevPropLeft) && (S.UseAntiBias == 0)
        % If experimenter changed PropLeft, then we need to recompute the
        % side of the future trials
        ntrialsRemaining = numel(TrialSidesList(currentTrial:end));
        coin_anitibias = rand(1,ntrialsRemaining);
        FutureTrials = coin_anitibias > (1-S.PropLeft);
        FutureTrials  = FutureTrials(randperm(ntrialsRemaining));
        TrialSidesList(currentTrial:end) = FutureTrials;
        PrevPropLeft = S.PropLeft;
        
    end %end S.UseAntiBias, S.PropLeft
    
    if TrialsDone > 0
        %cla(BpodSystem.GUIHandles.OutcomePlot);
        UpdateOutcomePlot(uint8(TrialSidesList), BpodSystem.Data);
    end
    
    % Pick this trial type
    thisTrialSide = TrialSidesList(currentTrial);
    
    
    if currentTrial < S.NumWarmup
        audEventRateList = [min(audEventRateList) max(audEventRateList)];
        visEventRateList = [min(visEventRateList) max(visEventRateList)];
        multEventRateList = [min(multEventRateList) max(multEventRateList)];
        warmUpTrial = 1; %%%%% Do we still need a warmup trial?
    else
        warmUpTrial = 0;
    end
    
    if thisTrialSide == 1 % Leftward trial
        LeftPortAction = 'Reward';
        RightPortAction = 'SoftPunish';
        RewardValve = LeftPortValveState; %left-hand port represents port#0, therefore valve value is 2^0
        rewardValveTime = LeftValveTime;
        RewardPortLED = 'PWM1'; % to turn on port LED when reward available- 28Jan2015
        correctSide = 1;
        RewardAmount = LeftRewardVolume;
        if strcmpi(S.highRateSide ,'R')
            audEventList = audEventRateList(audEventRateList <= categoryBoundary);
            visEventList = visEventRateList(visEventRateList <= categoryBoundary);
            multEventList = multEventRateList(multEventRateList <= categoryBoundary);
        else
            audEventList = audEventRateList(audEventRateList >= categoryBoundary);
            visEventList = visEventRateList(visEventRateList >= categoryBoundary);
            multEventList = multEventRateList(multEventRateList >= categoryBoundary);
        end
    else % Rightward trial (thisTrialSide == 0)
        LeftPortAction = 'SoftPunish';
        RightPortAction = 'Reward';
        RewardValve = RightPortValveState; %right-hand port represents port#2, therefore valve value is 2^2
        rewardValveTime = RightValveTime;
        RewardPortLED = 'PWM3'; % to turn on port LED when reward available- 28Jan2015
        correctSide = 2;
        RewardAmount = RightRewardVolume;
        
        if strcmpi(S.highRateSide ,'R')
            audEventList = audEventRateList(audEventRateList >= categoryBoundary);
            visEventList = visEventRateList(visEventRateList >= categoryBoundary);
            multEventList = multEventRateList(multEventRateList >= categoryBoundary);
        else
            audEventList = audEventRateList(audEventRateList <= categoryBoundary);
            visEventList = visEventRateList(visEventRateList <= categoryBoundary);
            multEventList = multEventRateList(multEventRateList <= categoryBoundary);
        end
    end
    
    %Choose modality-specific event rate for this trial
    if coin_modality < S.PropOnlyAuditory % only audio
        
        % randomly shuffle eligible events and pick one
        index = randperm(length(audEventList));
        thisTrialRate = audEventList(index(1));
        
    elseif coin_modality < S.PropOnlyVisual + S.PropOnlyAuditory % only visual
        
        % randomly shuffle eligible events and pick one
        index = randperm(length(visEventList));
        thisTrialRate = visEventList(index(1));
        
    else % audio & visual
        
        % randomly shuffle eligible events and pick one
        index = randperm(length(multEventList));
        thisTrialRate = multEventList(index(1));
    end
    toc
    
    
    
    
    %% Get the list of random events given the rate for this trial, long/short interval version
    %%%%%%%Edits made by Dennis to incorporate bcontrol code
    tic
    disp('Getting event and plotting time:');
    if S.IsPoissonStim == 0
        
        HighSilenceDuration = 0.05; %seconds
        LowSilenceDuration = 0.1;
        ToneDuration = 0.015;
        NoiseMaskAmp = 10;
        TotalStimDuration = 1.0;
        M = create_stim_matrix (HighSilenceDuration*1000, LowSilenceDuration*1000, ToneDuration*1000, TotalStimDuration*1000);
        
        [stimEventList, actual_events, actual_duration] = get_possible_stim (M, thisTrialRate);
        
        stimEventList;
        nr_of_events = actual_events;
        stim_duration = actual_duration;
        is_synch = S.SynchMultiSensory;
        
        %     is_synch = 1;
        % is_synch = rand < 0.5;
        
        % synchronous condition
        if is_synch == 1
            %is_synch = 1;
            aud_isis = stimEventList;
            vis_isis = stimEventList;
            offset = 0;
        elseif is_synch == 0
            % asynchronous condition
            % is_synch = 0;
            aud_isis = stimEventList;
            vis_isis = stimEventList(randperm(length(stimEventList)));
            offset = 0.02;
            
        elseif is_synch == 2
            % Independent condition
            aud_isis = stimEventList;
            if show_visual && show_audio
                if rand<0.5
                    vis_isis = stimEventList(randperm(length(stimEventList)));
                else
                    [vis_isis, actual_events, actual_duration] = get_possible_stim (M, 12);
                    nr_of_events = actual_events;
                    stim_duration = actual_duration;
                end
            else
                vis_isis = stimEventList;
            end
            offset = 0.02;
        end
        
        stim_duration = stim_duration + offset;
        
    else % the Possion situation
        % compute stimEventList: inter-event intervals.
        
        % all of the below are in sec
        is_synch = S.SynchMultiSensory;
        MinInterval = 0.025;   %0.032
        MaxInterval = 1;   %0.250
        ToneDuration = 0.015;  %0.015
        TotalStimDuration = 1;
        
        NoiseMaskAmp = 10;
        %StimRate = StimRate + 1;   % the number of intervals = the number of stimuli + 1
        
        stimEventList = set_Possion_stim(TotalStimDuration*1000, ToneDuration*1000, MinInterval*1000, thisTrialRate);
        
        % Set is_synch and add offset to the stimulus if needed
        % single modality conditions.
        
        
        offset = 0;     % In Poisson trials, the offset is always 0.   (C.Y.)
        if is_synch == 1     % Synchronous
            vis_isis = stimEventList;
            aud_isis = stimEventList; % use the same intervals for both auditory and visual.
            
            
        elseif is_synch == 0 % Asynchronous
            if rand < 0.5
                
                vis_isis = stimEventList;
                if stimEventList(1) == 0    % if the first interval is 0ms, do not shuffle it.
                    stimEventList_2 = stimEventList(2:end);
                    aud_isis = [0 stimEventList_2(randperm(length(stimEventList_2)))];
                else
                    aud_isis = stimEventList(randperm(length(stimEventList)));
                end
                
            else
                vis_isis = stimEventList;
                aud_isis = set_Possion_stim(TotalStimDuration*1000, ToneDuration*1000, MinInterval*1000, thisTrialRate);
                % In this case, we just set a new Poisson sequence for aud_isis
            end
            
            
        elseif is_synch == 2 % Independent
            if rand < 0.5
                
                vis_isis = stimEventList;
                if stimEventList(1) == 0    % if the first interval is 0ms, do not shuffle it.
                    stimEventList_2 = stimEventList(2:end);
                    aud_isis = [0 stimEventList_2(randperm(length(stimEventList_2)))];
                else
                    aud_isis = stimEventList(randperm(length(stimEventList)));
                end
                
            else
                aud_isis = stimEventList;
                a = 12;
                vis_isis = set_Possion_stim(TotalStimDuration*1000, ToneDuration*1000, MinInterval*1000, a);
                % In this case, we set a neutral stimuli for visual stimuli
            end
        end
        
    end
    %% Get the list of random events end
    %%
    
    if S.IsPoissonStim == 0
        audio_waveform = create_audio_signal(aud_isis, SamplingFreq, ToneDuration, ...
            HighSilenceDuration, LowSilenceDuration, 'White noise', S.StimLoudness, offset, NoiseMaskAmp, S.WhiteNoiseLinearModelParams);
        
        visual_waveform = create_visual_signal(vis_isis, SamplingFreq, S.StimBrightness, ...
            ToneDuration, LowSilenceDuration, HighSilenceDuration);
        
    else
        audio_waveform = Poisson_audsignal(aud_isis, SamplingFreq, ToneDuration, ...
            'White noise', S.StimLoudness, offset, NoiseMaskAmp, S.WhiteNoiseLinearModelParams);
        
        visual_waveform = Poisson_vissignal(vis_isis, SamplingFreq, S.StimBrightness, ToneDuration);
    end
    
    
    if length(visual_waveform) > length(audio_waveform)
        visual_waveform = visual_waveform(1:length(audio_waveform));
    else
        visual_waveform = [visual_waveform zeros(1, length(audio_waveform) - length(visual_waveform))];
    end
    
    Signal = [show_visual*visual_waveform; show_audio*audio_waveform];
    
    disp(['This event rate: ' num2str(thisTrialRate) ' events/s'])
    
    
    plot_StimulusPlotA = plot(BpodSystem.GUIHandles.StimulusPlotA, linspace(0,1,length(audio_waveform)), show_audio*audio_waveform,'color',[0 0.8 0]);title('Auditory stimulus');
    plot_StimulusPlotV = plot(BpodSystem.GUIHandles.StimulusPlotV, linspace(0,1,length(visual_waveform)), show_visual*visual_waveform, 'color',[0 0 0.8]);title('Visual stimulus');
    set(BpodSystem.GUIHandles.StimulusPlotA, 'box', 'off','xtick',[]);
    set(BpodSystem.GUIHandles.StimulusPlotV, 'box', 'off');
    %linkdata on
    drawnow
    
    if S.ExtraStimDuration > 0.0001
        %add extra stimulus
        extraStimRatio = S.ExtraStimDuration / desiredStimDuration;
        extraStimLength = round(extraStimRatio * length(Signal));
        extraSignal = repmat(Signal,1,(ceil(extraStimRatio)));
        SignalplusExtra = cat(2,Signal, zeros(2,round(eventDuration*SamplingFreq)),extraSignal(:,1:extraStimLength));
        S.ExtraStimDuration = S.ExtraStimDuration - S.ExtraStimDurationStep;
        Signal = SignalplusExtra;
    else
        S.ExtraStimDuration = 0;
    end
    
    if ~S.PlayStimulus
        Signal = 0;
        Modality = '-';
    end
    
    PsychToolboxSoundServer('Load', 1, Signal); % send signal to sound server
    
    % Determine whether to play start cue or cue
    if ~S.WaitStartCue
        StartCueOutputAction  = {};
    else
        StartCueOutputAction = {'SoftCode', 2};
    end
    
    if ~S.WaitEndGoCue
        GoCueOutputAction  = {};
    else
        GoCueOutputAction = {'SoftCode', 3};
    end
    toc
    
    
    % Build state matrix
    sma = NewStateMatrix();
    if S.AutoRun % Auto run means than the stim is played without the
        % animal going to the middle nose poke.
        %No initiation needed in auto run mode, changed 10/22/2020
        
        sma = AddState(sma, 'Name', 'PlayWaitStartCue', ...
            'Timer', preStimDelay, ...
            'StateChangeConditions', {'Tup','PlayStimulus'},...
            'OutputActions', StartCueOutputAction);
        
        sma = AddState(sma, 'Name', 'PlayStimulus', ...
            'Timer', 0, ...
            'StateChangeConditions', {'Tup','WaitCenter'},...
            'OutputActions', {'SoftCode', 1});
        if thisTrialSide == 1 %correct side is left
            sma = AddState(sma, 'Name', 'WaitCenter', ...
                'Timer', S.timeToChoose, ...
                'StateChangeConditions', { 'Tup', 'DidNotChoose', 'Port1In', LeftPortAction}, ...
                'OutputActions',{});
        else
            sma = AddState(sma, 'Name', 'WaitCenter', ...
                'Timer', S.timeToChoose, ...
                'StateChangeConditions', { 'Tup', 'DidNotChoose', 'Port3In', RightPortAction}, ...
                'OutputActions',{});
        end
    elseif S.initCenterPlayStimUntilCorrect %condition where the animal
        %pokes in the center and then the stimulus is played until the
        %animal either finds the correct side or the stimulus ends after
        %the time to choose.
        
        sma = AddState(sma, 'Name', 'GoToCenter', ...
            'Timer', 0,...
            'StateChangeConditions', {'Port2In', 'PlayWaitStartCue'},...
            'OutputActions', {});
        
        sma = AddState(sma, 'Name', 'PlayWaitStartCue', ...
            'Timer', preStimDelay, ...
            'StateChangeConditions', {'Tup','PlayStimulus'},...
            'OutputActions', StartCueOutputAction);
        
        sma = AddState(sma, 'Name', 'PlayStimulus', ...
            'Timer', 0, ...
            'StateChangeConditions', {'Tup','WaitCenter'},...
            'OutputActions', {'SoftCode', 1});
        
        if thisTrialSide == 1 %correct side is left
            sma = AddState(sma, 'Name', 'WaitCenter', ...
                'Timer', S.timeToChoose, ...
                'StateChangeConditions', { 'Tup', 'DidNotChoose', 'Port1In', LeftPortAction}, ...
                'OutputActions',{});
        else
            sma = AddState(sma, 'Name', 'WaitCenter', ...
                'Timer', S.timeToChoose, ...
                'StateChangeConditions', { 'Tup', 'DidNotChoose', 'Port3In', RightPortAction}, ...
                'OutputActions',{});
        end
    else
        sma = AddState(sma, 'Name', 'GoToCenter', ...
            'Timer', 0,...
            'StateChangeConditions', {'Port2In', 'PlayWaitStartCue'},...
            'OutputActions', {});
        
        sma = AddState(sma, 'Name', 'PlayWaitStartCue', ...
            'Timer', preStimDelay, ...
            'StateChangeConditions', {'Tup','PlayStimulus', 'Port2Out', 'EarlyWithdrawal'},...
            'OutputActions', StartCueOutputAction);
        
        sma = AddState(sma, 'Name', 'PlayStimulus', ...
            'Timer', 0, ...
            'StateChangeConditions', {'Tup','WaitCenter', 'Port2Out', 'EarlyWithdrawal'},...
            'OutputActions', {'SoftCode', 1,'BNCState',1});
        
        sma = AddState(sma, 'Name', 'WaitCenter', ...
            'Timer', S.minWaitTime, ...
            'StateChangeConditions', {'Port2Out', 'EarlyWithdrawal', 'Tup', 'PlayGoTone'}, ...
            'OutputActions',{});
        
        
        if ~S.PortLEDCue %added 28Jan2015
            sma = AddState(sma, 'Name', 'PlayGoTone', ...
                'Timer', CenterValveTime, ...
                'StateChangeConditions', {'Tup', 'WaitForWithdrawalFromCenter'},...
                'OutputActions', [GoCueOutputAction,'ValveState', CenterPortValveState]);
        else
            sma = AddState(sma, 'Name', 'PlayGoTone', ...
                'Timer', CenterValveTime, ...
                'StateChangeConditions', {'Tup', 'CueRewardPortLED'},...
                'OutputActions', [GoCueOutputAction,'ValveState', CenterPortValveState]);
            
            sma = AddState(sma, 'Name', 'CueRewardPortLED', ...
                'Timer', 0.1, ...
                'StateChangeConditions', {'Tup', 'WaitForWithdrawalFromCenter'},...
                'OutputActions', {RewardPortLED,255});
        end
        
        if directTrial == 1
            sma = AddState(sma, 'Name', 'WaitForWithdrawalFromCenter', ...
                'Timer', S.timeToChoose,...
                'StateChangeConditions', {'Port2Out', 'DirectReward', 'Tup', 'DidNotChoose'},...
                'OutputActions', {});
            
            sma = AddState(sma, 'Name', 'DirectReward', ...
                'Timer', 0, ...
                'StateChangeConditions', {'Tup', 'Reward'},...
                'OutputActions', {'SoftCode', 255});
            
        else
            sma = AddState(sma, 'Name', 'WaitForWithdrawalFromCenter', ...
                'Timer', S.timeToChoose,...
                'StateChangeConditions', {'Port2Out', 'WaitForResponse', 'Tup', 'DidNotChoose'},...
                'OutputActions', {});
        end
    end
    
    if S.holdCenterStimUntilCorrect
        %Condition where animal has to remain in fixation at the center but
        %can also choose incorrect one wthin the provided time to choose
        if thisTrialSide == 1 %correct side is left
            sma = AddState(sma, 'Name', 'WaitForResponse', ...
                'Timer', S.timeToChoose, ...
                'StateChangeConditions', { 'Tup', 'DidNotChoose', 'Port1In', LeftPortAction}, ...
                'OutputActions',{});
        else
            sma = AddState(sma, 'Name', 'WaitForResponse', ...
                'Timer', S.timeToChoose, ...
                'StateChangeConditions', { 'Tup', 'DidNotChoose', 'Port3In', RightPortAction}, ...
                'OutputActions',{});
        end
        
    else
        sma = AddState(sma, 'Name', 'WaitForResponse', ...
            'Timer', S.timeToChoose,...
            'StateChangeConditions', {'Port1In', LeftPortAction, 'Port3In', RightPortAction, 'Tup', 'DidNotChoose'},...
            'OutputActions', {}); %stop stimulus when subjects responds, to accomodate extra stimulus...added 14-Jan-2015
    end
    
    sma = AddState(sma, 'Name', 'Reward', ...
        'Timer', rewardValveTime,...
        'StateChangeConditions', {'Tup','PrepareNextTrial'},...
        'OutputActions', {'ValveState', RewardValve,'SoftCode', 255});
    
    % For soft punishment just give time out
    sma = AddState(sma, 'Name', 'SoftPunish', ...
        'Timer', S.PunishDuration + 0.05,...
        'StateChangeConditions', {'Tup','PrepareNextTrial'},...
        'OutputActions', {'SoftCode', 5});
    
    sma = AddState(sma, 'Name', 'EarlyWithdrawal', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'HardPunish'},...
        'OutputActions', {'SoftCode', 255});
    
    % For hard punishment play noise and give time out
    sma = AddState(sma, 'Name', 'HardPunish', ...
        'Timer', S.EarlyPunishDuration, ...
        'StateChangeConditions', {'Tup', 'PrepareNextTrial'}, ...
        'OutputActions', {'SoftCode', 4});
    
    sma = AddState(sma, 'Name', 'DidNotChoose', ...
        'Timer', 0, ...
        'StateChangeConditions', {'Tup', 'SoftPunish'}, ...
        'OutputActions', {'SoftCode', 255});
    
    sma = AddState(sma, 'Name', 'PrepareNextTrial', ...
        'Timer', 1, ...
        'StateChangeConditions', {'Tup', 'exit'}, ...
        'OutputActions', {'SoftCode', 255} );
    
    
    % Send and run state matrix
    BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
    
    SendStateMatrix(sma);
    % Add to the camera log
    if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
        if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
            fwrite(udpObj,sprintf('log=trial_start:%d',currentTrial))
        end
    end
    
    RawEvents = RunStateMatrix;
    
    if isfield(BpodSystem.ProtocolSettings,'labcamsAddress')
        if ~isempty(BpodSystem.ProtocolSettings.labcamsAddress)
            fwrite(udpObj,sprintf('log=trial_end:%d',currentTrial))
        end
    end
    % Save events and data
    if ~isempty(fieldnames(RawEvents))
        tic
        disp('Data saving time:');
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents);
        TrialsDone = TrialsDone + 1; %increment number of trials done
        
        % need to save these next five variables as they are no longer
        % included in the settings file.
        BpodSystem.Data.Modality{TrialsDone} = Modality;
        BpodSystem.Data.EventDuration(TrialsDone) = eventDuration;
        BpodSystem.Data.CategoryBoundary(TrialsDone) = categoryBoundary;
        BpodSystem.Data.DesiredStimDuration(TrialsDone) = desiredStimDuration;
        
        Rewarded(TrialsDone) = ~isnan(BpodSystem.Data.RawEvents.Trial{1,currentTrial}.States.Reward(1));
        EarlyWithdrawal(TrialsDone) = ~isnan(BpodSystem.Data.RawEvents.Trial{1,currentTrial}.States.EarlyWithdrawal(1));
        DidNotChoose(TrialsDone) = ~isnan(BpodSystem.Data.RawEvents.Trial{1,currentTrial}.States.DidNotChoose(1));
        
        BpodSystem.Data.stimEventList{TrialsDone} = stimEventList;
        BpodSystem.Data.auditoryIsis{TrialsDone} = aud_isis;
        BpodSystem.Data.visualIsis{TrialsDone} = vis_isis;
        
        if S.IsPoissonStim == 0      % The reguler task and Possion task use different aud_isis/vis_isis.
            % So the number of events have to be calculated differently.
            BpodSystem.Data.nAuditoryEvents(TrialsDone) = length(aud_isis)+1;
            BpodSystem.Data.nVisualEvents(TrialsDone) = length(vis_isis)+1;
        else
            BpodSystem.Data.nAuditoryEvents(TrialsDone) = length(aud_isis)-1;
            BpodSystem.Data.nVisualEvents(TrialsDone) = length(vis_isis)-1;
        end
        
        BpodSystem.Data.Rewarded(TrialsDone) = Rewarded(TrialsDone);
        BpodSystem.Data.EarlyWithdrawal(TrialsDone) = EarlyWithdrawal(TrialsDone);
        BpodSystem.Data.DidNotChoose(TrialsDone) = DidNotChoose(TrialsDone);
        BpodSystem.Data.EventRate(TrialsDone) = thisTrialRate;
        BpodSystem.Data.PreStimDelay(TrialsDone) = preStimDelay;
        BpodSystem.Data.SetWaitTime(TrialsDone) = S.minWaitTime;
        BpodSystem.Data.TotalStimDuration(TrialsDone) = TotalStimDuration*1000;
        BpodSystem.Data.DirectReward(TrialsDone) = directTrial;
        %BpodSystem.Data.DesiredStimGenerated(TrialsDone) = stimflag;
        BpodSystem.Data.ExtraStimDuration(TrialsDone) = S.ExtraStimDuration;
        BpodSystem.Data.CenterRewarded(TrialsDone) = centerRewarded;
        BpodSystem.Data.WarmUpTrial(TrialsDone) = warmUpTrial;
        BpodSystem.Data.AutoRunModeON(TrialsDone) = S.AutoRun;
        
        
        %compute time spent in center for all each trial with one nose poke in
        %and out of the center port. better to compute this now
        BpodSystem.Data.ActualWaitTime(TrialsDone) = nan;
        if isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events,'Port2Out') && isfield(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events,'Port2In')
            if (numel(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2Out)== 1) && (numel(BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2In) == 1)
                BpodSystem.Data.ActualWaitTime(TrialsDone) = BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2Out - BpodSystem.Data.RawEvents.Trial{1,TrialsDone}.Events.Port2In;
            end
        end
        
        modalityRecord(TrialsDone) = modalityNum;
        correctSideRecord(TrialsDone) = correctSide;
        BpodSystem.Data.CorrectSide(TrialsDone) = correctSideRecord(TrialsDone);
        
        if BpodSystem.Data.Rewarded(TrialsDone) == 1
            %correct!
            OutcomeRecord(TrialsDone) = 1;
        elseif BpodSystem.Data.EarlyWithdrawal(TrialsDone) == 1
            %early withdrawal
            OutcomeRecord(TrialsDone) = -1;
        elseif BpodSystem.Data.DidNotChoose(TrialsDone) == 1
            %did not choose
            OutcomeRecord(TrialsDone) = -2;
        else
            %incorrect
            OutcomeRecord(TrialsDone) = 0;
        end
        
        if OutcomeRecord(TrialsDone) >= 0 %if the subject responded
            if ((correctSideRecord(TrialsDone)==1) && Rewarded(TrialsDone)) || ((correctSideRecord(TrialsDone)==2) && ~Rewarded(TrialsDone))
                ResponseSideRecord(TrialsDone) = 1;
            elseif ((correctSideRecord(TrialsDone)==1) && ~Rewarded(TrialsDone)) || ((correctSideRecord(TrialsDone)==2) && Rewarded(TrialsDone))
                ResponseSideRecord(TrialsDone) = 2;
            end
        end
        
        BpodSystem.Data.ResponseSide(TrialsDone) = ResponseSideRecord(TrialsDone);
        
        RewardAmounts(TrialsDone) = RewardAmount*Rewarded(TrialsDone);
        toc
        
        
        % If previous trial was not an early withdrawal, increase wait duration
        if ~BpodSystem.Data.EarlyWithdrawal(TrialsDone)
            S.minWaitTime = S.minWaitTime + S.minWaitTimeStep;
        end
        
        if S.minWaitTime > 1.1 && isequal(WaitTimeMode, 'Fixed') == 1
            S.minWaitTime = 1.1;
            S.minWaitTimeStep = 0;
        end
        
        if isequal(WaitTimeMode, 'Exp') == 1
            S.minWaitTime = 'Exp';
        end
        tic
        disp('Result plotting time:');
        set(BpodSystem.GUIHandles.LabelsVal.TrialsDone,'String',num2str(TrialsDone'));
        set(BpodSystem.GUIHandles.LabelsVal.CompletedTrials,'String',num2str(TrialsDone - nansum(EarlyWithdrawal)-nansum(DidNotChoose)));
        set(BpodSystem.GUIHandles.LabelsVal.RewardedTrials,'String',num2str(nansum(Rewarded)));
        set(BpodSystem.GUIHandles.LabelsVal.WaterAmount,'String',[num2str((nansum(Rewarded) * (mean([S.leftRewardVolume S.rightRewardVolume])))/1000) ' ml']);
        drawnow;
        
        PerformancePlot(BpodSystem.GUIHandles.PerformancePlot, 'update', currentTrial, TrialSidesList, OutcomeRecord);
        toc
        if TrialsDone > S.PlotPMFnTrials && (directTrial==0)
            if mod(TrialsDone,S.UpdatePMfnTrials) == 1
                %every n-th trial after TrialsDone, update the PMF plot
                pmfPlot;
            end
        end
    end
    
    
    % Save protocol settings file to directory
    %SaveProtocolSettings(S);    % Moved to the GUI, changed by C.Y.
    if BpodSystem.Status.BeingUsed == 0
        
        % Close video
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
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
        %        BpodParameterGUI_Visual('close',S)
        PsychToolboxSoundServer('Close');
        
        return;
    end
    
    % Deleting the stimulus plotting every trial to save GPU memory
    delete([plot_StimulusPlotA, plot_StimulusPlotV]);
    
end
end


%% Auxillary functions

function generateAndUploadSounds (samplingFreq, soundLoudness, gocueLoudness, earlyPunishLoudness, earlyPunishDuration, punishLoudness, punishDuration, CalibrationModelParams)
% Star wait cue
waveStartSound = 0.1 * soundLoudness * GenerateSineWave(samplingFreq, 7000, 0.1); % Sampling freq (hz), Sine frequency (hz), duration (s)
WaitStartSound = [zeros(1,size(waveStartSound,2)); waveStartSound];

% Go cue
waveStopSound = 0.15 * 10^(1/10*(CalibrationModelParams(1)*gocueLoudness + CalibrationModelParams(2))) * GenerateSineWave(samplingFreq, 7000, 0.1);
WaitStopSound = [zeros(1,size(waveStopSound,2)); waveStopSound];

% Punishment for mistaken choice
wavePunishSound = 0.15 * 10^(1/10*(CalibrationModelParams(1)*punishLoudness + CalibrationModelParams(2))) * GenerateSineWave(samplingFreq, 15000, punishDuration);
PunishSound = [zeros(1,size(wavePunishSound,2)); wavePunishSound];

% Early withdrawal punishment tone
%  wavePunishSound = (rand(1,samplingFreq*.5)*2) - 1;
%  wavePunishSound = 0.075 * soundLoudness * GenerateSineWave(samplingFreq, 12000, 1);
% PunishSound = [zeros(1,size(wavePunishSound,2)); wavePunishSound];

load('C:\Users\Anne\Dropbox\rat_protocols\Bpod\TheMudSkipper2\WhiteNoiseCalibration.mat');

DefaultSettings.WhiteNoiseLinearModelParams = polyfit(reshape(TargetSPLs,1,[]),reshape(10*log10(NoiseAmplitudes),1,[]),1);
PunishNoiseModelParams = DefaultSettings.WhiteNoiseLinearModelParams;
pnoise_amplitude = 10^(1/10*(PunishNoiseModelParams(1)* earlyPunishLoudness + PunishNoiseModelParams(2)));%white noise
%         pnoise = 2 * pnoise_loudness * rand(1, pnoise_duration * srate) - pnoise_loudness;
EarlyPunishSound = [zeros(1,earlyPunishDuration*samplingFreq); 2*pnoise_amplitude * rand(1, earlyPunishDuration * samplingFreq)- pnoise_amplitude];

% Upload sounds to sound server. Channel 1 reserved for stimuli
PsychToolboxSoundServer('Load', 2, WaitStartSound);
PsychToolboxSoundServer('Load', 3, WaitStopSound);
PsychToolboxSoundServer('Load', 4, EarlyPunishSound);
PsychToolboxSoundServer('Load', 5, PunishSound);
end

function UpdateOutcomePlot(TrialTypes, Data)
global BpodSystem
Outcomes = zeros(1,Data.nTrials);
for x = 1:Data.nTrials
    if Data.Rewarded(x)
        Outcomes(x) = 1;
    elseif Data.EarlyWithdrawal(x)
        Outcomes(x) = -1;
    elseif Data.DidNotChoose(x)
        Outcomes(x) = -2;
    else
        Outcomes(x) = 0;
    end
end
OutcomePlot(BpodSystem.GUIHandles.OutcomePlot, 'update', Data.nTrials+1, TrialTypes, Outcomes);
drawnow
end

function pmfPlot

global BpodSystem
eventRates = BpodSystem.Data.EventRate;
responseSides =   BpodSystem.Data.ResponseSide;
respondedTrials = (responseSides == 1 | responseSides == 2); %trials in which the subject made a decision
directReward = (BpodSystem.Data.DirectReward);

uniquerates = unique(eventRates);
propRight = nan(1,numel(uniquerates));

for rr = 1:numel(uniquerates)
    this_rate = uniquerates(rr);
    this_rate_trials = (eventRates == this_rate);
    nRights = sum(responseSides(respondedTrials & this_rate_trials & ~directReward) == 2);
    nTotal = sum(responseSides(respondedTrials & this_rate_trials & ~directReward) > 0); %using responseside takes care of incompleted/did not choose trials
    propRight(rr) = nRights./nTotal;
end

set(BpodSystem.GUIHandles.PMFPlotData,'xdata',uniquerates,'ydata',propRight);
drawnow %plot data

end

function [eventList,got_it]= getRandomStimEvents(thisRate, stimDuration, eventDuration)
frames = floor(stimDuration/eventDuration/2);
maxAttempts = 1000;
got_it = 0;
for attempt = 1:maxAttempts
    eventList = [1 (poissrnd(rand, 1, frames-1) > 0)];
    if sum(eventList) == thisRate
        got_it = 1;
        break;
    end
end

if ~got_it
    %try again to generate the stimulus, using higher lambda value.
    got_it = 0;
    for attempt = 1:maxAttempts
        eventList = [1 (poissrnd(5*rand, 1, frames-1) > 0)];
        if sum(eventList) == thisRate
            got_it = 1;
            break;
        end
    end
end


if ~got_it
    %if the attempts fail. do not present stimulus.
    disp('Not enough attempts to generate the desired stimulus');
    eventList = zeros(1,frames); % no stimulus
end

end

function waveform = buildAudioWaveForm(eventList, eventDuration, samplingFreq)
% white noise sound event
event_part = (rand(1,samplingFreq*eventDuration) * 2) - 1;
% event_part = 2*GenerateSineWave(samplingFreq, 1000, eventDuration);
silence_part = zeros(1,length(event_part));
waveform = [];
for ev = 1:length(eventList)
    this_event = eventList(ev);
    if this_event == 1
        waveform = [waveform event_part silence_part];
    else
        waveform = [waveform silence_part silence_part];
    end
end
end

function waveform = buildVisualWaveForm(eventList, eventDuration, samplingFreq, brightness, pwm)
%07-Sept-2016: added pwm flag. for new ALA Scientific LED panel driver

% visual event
event_part = GenerateSineWave(samplingFreq, 200*brightness, eventDuration);

if pwm
    [pks,locs] = findpeaks(event_part);
    
    flash = zeros(size(event_part));
    flash(locs) = 1;
    event_part = flash;
else
    event_part(event_part < 0.975) = 0;
end

if numel(eventList) == 1
    waveform = event_part;
    return
end

silence_part = zeros(1,length(event_part));
waveform = [];
for ev = 1:length(eventList)
    this_event = eventList(ev);
    if this_event == 1
        waveform = cat(2,waveform, event_part, silence_part);
    else
        waveform = cat(2,waveform, silence_part, silence_part);
    end
end
end


% Matt Kaufman's MOD solution for this is very elegant and works great.
function random_delay = generate_random_delay (lambda, minimum, maximum)
random_delay = 0;
if ~((minimum == 0) && (maximum ==0))
    x = -log(rand)/lambda;
    random_delay = mod(x, maximum - minimum) + minimum;
end
end



%Anti-bias functions from Matt Kaufman
function [newModeRightArray, newSuccessArray] = ...
    updateAntiBiasArrays(modeRightArray, successArray, visOrAud, outcome, ...
    prevCorrectSide, prevLR, prevSuccess, antiBiasTau, wentRight)
% Based on what happened on the last completed trial, update our beliefs
% about the animal's biases. modeRightArray tracks how likely he is to go
% right for each modality. successArray tracks how likely he is to succeed
% for left or right given what he did on the previous trial.
%
% Note: we'll actually use antiBiasTau * 3 for updating the
% modality-related side bias. If we don't, and there's only one modality,
% the updates will cause oscillation against a perfectly consistent
% strategy.

% For an exponential function, the pdf = (1/tau)*e^(-t/tau)
% The integral from 0 to 1 is [1 - e^(-1/tau)]
% This lets us do exponential decay using only the current
% outcome and previous biases
antiAlternationW = 1 - exp(-1/(3*antiBiasTau));
antiBiasW = 1 - exp(-1/antiBiasTau);

% modeRightArray -- how often he's gone right for each modality
% modality = 2 + visOrAud;
modality = visOrAud;
newModeRightArray = modeRightArray;
if ~isnan(wentRight)
    newModeRightArray(modality) = antiAlternationW * wentRight + (1 - antiAlternationW) * modeRightArray(modality);
end

% Can only update arrays if we already had a trial in the history (since we
% have a two-trial dependence)
newSuccessArray = successArray;
if ~isnan(prevLR)
    newSuccessArray(prevLR, prevSuccess + 1, prevCorrectSide) = antiBiasW * (outcome > 0) + ...
        (1-antiBiasW) * successArray(prevLR, prevSuccess + 1, prevCorrectSide);
end

end


function pLeft = getAntiBiasPLeft(successArray, modeRightArray, modality, ...
    antiBiasStrength, prevLR, prevSuccess)

% Find the relevant part of the SuccessArray and ModeRightArray
successPair = squeeze(successArray(prevLR, prevSuccess + 1, :));

modeRight = modeRightArray(modality);

% Based on the previous successes on this type of trial,
% preferentially choose the harder option

succSum = sum(successPair);

pLM = modeRight;  % prob desired for left based on modality-specific bias
pLT = successPair(2) / succSum;  % same based on prev trial
iVar2M = 1 / (pLM - 1/2) ^ 2; % inverse variance for modality
iVar2T = 1 / (pLT - 1/2) ^ 2; % inverse variance for trial history

if succSum == 0 || iVar2T > 10000
    % Handle degenerate cases, trial history uninformative
    pLeft = pLM;
elseif iVar2M > 10000
    % Handle degenerate cases, modality bias uninformative
    pLeft = pLT;
else
    % The interesting case... combine optimally
    pLeft = pLM * (iVar2T / (iVar2M + iVar2T)) + pLT * iVar2M / (iVar2M + iVar2T);
end

% Weight pLeft from anti-bias by antiBiasStrength
pLeft = antiBiasStrength * pLeft + (1 - antiBiasStrength) * 0.5;

end

%Stimulus Matrix
function M = create_stim_matrix (shorti, longi, event, duration)

% let's go through all the possible stimulus for these settings
% by iterating the number of LONG intervals

max_nr_shorti = floor((duration - event) / (shorti + event));

nr_shorti = [0 : max_nr_shorti];
nr_longi  = floor(((duration - event) -  nr_shorti .* (shorti + event)) ./ (longi + event));

stim_strength = nr_shorti ./ (nr_shorti + nr_longi);
actual_duration = nr_longi * (longi + event) + nr_shorti * (shorti + event) + event;

M = [stim_strength', nr_shorti', nr_longi', actual_duration', nr_longi' + nr_shorti' + 1];

% take only stimuli that are longer than 930 ms
M = M(M(:,4) > 930,:);

% M = unique(M, 'rows');

end

function [stim, actual_events, actual_duration] = get_possible_stim (stim_matrix, desired_events)

% possible_stim = stim_matrix(stim_matrix(:,1) < desired_strength + 0.05 & stim_matrix(:,1) >= desired_strength - 0.05,:);
possible_stim = stim_matrix(stim_matrix(:,5) == desired_events,:);

% if there is no possible stimulus with the dre if this is the best way to do
% it, though.esired strength
% then choose the closest one. Not su
if isempty(possible_stim)
    [min_difference, ind] = min(abs(stim_matrix(:,5) - desired_events));
    this_stim = stim_matrix(ind,:);
    % if there are possible stimuli, then pick one randomly
else
    ind = randperm(size(possible_stim,1));
    this_stim = possible_stim(ind(1),:);
end

% create the corresponding stimulus vector
stim = [repmat(1, 1, this_stim(2)), repmat(2, 1, this_stim(3))];
stim
rand_indexes = randperm(length(stim));

stim = stim(rand_indexes);
actual_events = this_stim(5);
actual_duration = this_stim(4);

end

% Auditory signal
function signal_audio = create_audio_signal(isis, audiorate, tone_duration, short, long, sound_carrier,...
    sound_loudness, offset,  noise_loudness, CalibrationModelParams)

% play sound using this rate
% udiorate = 44100;

freq = 15000; % Hz

timevec = (0 : 1/audiorate : tone_duration);

signal_amplitude = 10^(1/10*(CalibrationModelParams(1)*sound_loudness + CalibrationModelParams(2)));
noise_amplitude = 10^(1/10*(CalibrationModelParams(1)*noise_loudness + CalibrationModelParams(2)));

envelope = sin([0:pi/(audiorate*tone_duration):pi]);
% wnoise = 2 * sound_loudness * rand(1,length(timevec)) - sound_loudness;
%
% if strcmp(sound_carrier, '15 KHz + envelope')
%     soundpart = sound_loudness * (sin(2*pi * freq * timevec) .* envelope);
% elseif strcmp(sound_carrier, '15 KHz')
%     soundpart = sound_loudness * (sin(2*pi * freq * timevec));
% else % if you choose White Noise
%     soundpart = wnoise; % .* envelope; % Why should I have an envelope for white noise?!
% end
if strcmp(sound_carrier, '15 KHz + envelope')
    soundpart = signal_amplitude * (sin(2*pi * freq * timevec) .* envelope);
elseif strcmp(sound_carrier, '15 KHz')
    soundpart = signal_amplitude * (sin(2*pi * freq * timevec));
else
    wnoise = signal_amplitude * 2 * (rand(1,length(timevec))-0.5);
    soundpart = wnoise .* envelope;
end
%figure; plot(soundpart);

offset_part = zeros(1, round(audiorate * offset));

short_silence_part = zeros(1, round(audiorate * short));
long_silence_part = zeros(1, round(audiorate * long));

signal_audio = [offset_part soundpart];

for i = 1:length(isis)
    
    if isis(i) == 1
        signal_audio = [signal_audio short_silence_part soundpart];
    elseif isis(i) == 2
        signal_audio = [signal_audio long_silence_part soundpart];
    end
    
end

signal_audio = signal_audio + noise_amplitude*2*(rand(size(signal_audio))-0.5);

end

function signal_visual = create_visual_signal(isis, rate, brightness, flash_duration, long_isi, short_isi)

timevec = (0 : 1/rate : flash_duration);
freq = 200*brightness; % we can't detect a 300 Hz flicker
sine_wave = sin(2*pi * freq * timevec);

[pks,locs] = findpeaks(sine_wave);

flash = zeros(size(sine_wave));
flash(locs) = 1;

%     shift = brightness .* 2 - 1;
%     timevec = (0 : 1/rate : flash_duration);
%     freq = 10000; % we can't detect a 300 Hz flicker
%     sine_wave = sin(2*pi * freq * timevec);
%
%     on_off = sine_wave > - shift;
%     %flash = sine_wave .* on_off;
%     flash = on_off;
%
%     %flash = sine_wave;
%     % figure; plot(flash);

long_dark = zeros(1, round(rate * long_isi));
short_dark = zeros(1, round(rate * short_isi));

signal_visual = flash;
for i = isis
    if i == 1
        signal_visual = [signal_visual short_dark flash];
    elseif i == 2
        signal_visual = [signal_visual long_dark flash];
    end
end

end




%% New Possion Producing Code by C.Y.
function stimEventList = set_Possion_stim(TotalStimDuration, ToneDuration, MinInterval, StimRate)

try
    bin_array = zeros(1, TotalStimDuration/(ToneDuration + MinInterval));
catch
    disp('The time length of one trial is not divisible by the bin!');
end


if StimRate > length(bin_array)
    StimRate = length(bin_array);
    disp('The number of stimili you want is greater than the maximum! The maximum is used instead.');
end


bin_array(1 : StimRate) = 1;
bin_array = bin_array(randperm(length(bin_array)));

a = find(bin_array == 1);
stimEventList = zeros(1, (length(a)+1));
for i = 1 : length(stimEventList)
    
    if i == 1
        stimEventList(i) = (ToneDuration + MinInterval) * (a(i) - 1);
    elseif i > 1 && i < length(stimEventList)
        stimEventList(i) = MinInterval + (ToneDuration + MinInterval) * (a(i) - a(i-1) - 1);
    elseif i == length(stimEventList)
        stimEventList(i) = TotalStimDuration - (ToneDuration + MinInterval) * a(i-1) + MinInterval;
    end
    
end

end

%% Poisson Stimuli Funtions added by C.Y.

%% Auditory Poisson signal
function signal_audio = Poisson_audsignal(isis, audiorate, tone_duration, sound_carrier,...
    sound_loudness, offset,  noise_loudness, CalibrationModelParams)

% play sound using this rate
% udiorate = 44100;

freq = 15000; % Hz

timevec = (0 : 1/audiorate : tone_duration);

signal_amplitude = 10^(1/10*(CalibrationModelParams(1)*sound_loudness + CalibrationModelParams(2)));
noise_amplitude = 10^(1/10*(CalibrationModelParams(1)*noise_loudness + CalibrationModelParams(2)));

envelope = sin([0:pi/(audiorate*tone_duration):pi]);

if strcmp(sound_carrier, '15 KHz + envelope')
    soundpart = signal_amplitude * (sin(2*pi * freq * timevec) .* envelope);
elseif strcmp(sound_carrier, '15 KHz')
    soundpart = signal_amplitude * (sin(2*pi * freq * timevec));
else
    wnoise = signal_amplitude * 2 * (rand(1,length(timevec))-0.5);
    soundpart = wnoise .* envelope;
end

offset_part = zeros(1, round(audiorate * offset));


signal_audio = [offset_part];

for i = 1: (length(isis) - 1)
    interval = zeros(1, round(isis(i)*audiorate/1000));
    signal_audio = [signal_audio interval soundpart];
end

interval = zeros(1, round(isis(length(isis))*audiorate/1000));
signal_audio = [signal_audio interval];

signal_audio = signal_audio + noise_amplitude*2*(rand(size(signal_audio))-0.5);

end


%% Visual Poisson signal
function signal_visual = Poisson_vissignal(isis, rate, brightness, flash_duration)

timevec = (0 : 1/rate : flash_duration);
freq = 200*brightness; % we can't detect a 300 Hz flicker
sine_wave = sin(2*pi * freq * timevec);

[pks,locs] = findpeaks(sine_wave);

flash = zeros(size(sine_wave));
flash(locs) = 1;


signal_visual = [];

for i = 1 : (length(isis) - 1)
    interval = zeros(1, round(isis(i)*rate/1000));
    signal_visual = [signal_visual interval flash];
end

interval = zeros(1, round(isis(length(isis))*rate/1000));
signal_visual = [signal_visual interval];

end


%% Getting the time length of delay period from an exponential distribution
%%% Added by C.Y. on 02/16/2020
function minWaitTime = WaitTime_Exponential(minimum, maximum, stepsize)

minWaitTime = 1000 + minimum;

timelength = 0;
probility = 0.9;
probility_acum = probility;
threshold = rand();
for n = 1 : floor((maximum-minimum)/stepsize)
    if threshold >= probility_acum
        break;
    else
        timelength = timelength + stepsize;
        probility_acum = probility_acum * probility;
    end
end

minWaitTime = (minWaitTime + timelength)/1000;

end