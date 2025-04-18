function ObserverFigure(figMethod)
% ObserverFigure('init') %Generates the data display and UIcontrols for the
% observer mouse
% ObserverFigure('refresh') %Refreshes the display of trial outcomes, etc.
% ObserverFigure('close') %Closes the figure created with the init call
% 
% INPUTS: -figMethod: The method for creation of the figure
%
% Please note that this function does not feature an updating and
% refreshing method. Both of these actions are provided by the call to the
% DemonstratorFigure function with the respective method.
%
% LO, 1/13/2021
%--------------------------------------------------------------------------
global BpodSystem

switch figMethod
    %% Initialize figure
    case 'init'
        %Generate figure
        screenParam = get(0,'screensize');
        
        BpodSystem.GUIHandles.Figures.ObsFigure = figure('Units','Pixels','Position',[screenParam(1)+10, screenParam(2)+50, 680,350],...
            'Name',[BpodSystem.ProtocolSettings.experimentName ' - ' BpodSystem.ProtocolSettings.obsID ' - Observer'],...
            'NumberTitle','off','MenuBar','none');
        
        %Place the panels and axes on the figure
%         BpodSystem.GUIHandles.ObsPreObsPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
%             'Position', [0.05, 0.05, 0.225, 0.26],'Title','Pre observing','FontWeight','bold');
        BpodSystem.GUIHandles.ObsTrainPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.05, 0.225, 0.45, 0.175],'Title','Observer fixation training','FontWeight','bold');
        BpodSystem.GUIHandles.ObsVirtualDemonPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.05, 0.05, 0.45, 0.175],'Title','Virtual demonstrator','FontWeight','bold');
        BpodSystem.GUIHandles.ObsInitiationWindowPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.5, 0.2832, 0.225, 0.116],'Title','Observer initiation window','FontWeight','bold');
        BpodSystem.GUIHandles.ObsRewardParamPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.5, 0.166, 0.225, 0.116],'Title','Reward parameters','FontWeight','bold');
        BpodSystem.GUIHandles.ObsWeightPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.5, 0.05, 0.225, 0.116],'Title','Observer weight','FontWeight','bold');
        
        BpodSystem.GUIHandles.ObsPerformancePanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.775, 0.16, 0.175, 0.24],'Title','Performance summary','FontWeight','bold');
        BpodSystem.GUIHandles.ObsRewardSummaryPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.775, 0.05, 0.175, 0.11],'Title','Reward summary','FontWeight','bold');
        
        BpodSystem.GUIHandles.InterTrialIntervalPlotObserver = axes('Parent', BpodSystem.GUIHandles.Figures.ObsFigure,...
            'Units', 'Normal', 'Position', [0.075, 0.53, 0.3, 0.4],'tickdir','out','NextPlot','add');
        xlabel('Trial number'); ylabel('Interval between trial initiations (s)'); title('Inter trial intervals');
        box off;
        BpodSystem.GUIHandles.InitiationTimePlotObserver = axes('Parent', BpodSystem.GUIHandles.Figures.ObsFigure,...
        'Units', 'Normal', 'Position', [0.45, 0.53, 0.15, 0.4],'tickdir','out','NextPlot','add');
        xlabel('Density estimate'); ylabel('Time to initiate fixation (s)'); title('Initiation time');
        box off; BpodSystem.GUIHandles.InitiationTimePlotObserver.XTick = [];
        BpodSystem.GUIHandles.WaitTimePlotObserver = axes('Parent', BpodSystem.GUIHandles.Figures.ObsFigure,...
            'Units', 'Normal', 'Position', [0.675, 0.53, 0.3, 0.4],'tickdir','out','NextPlot', 'add');
        xlabel('Trial number'); ylabel('Wait times (s)'); title('Observer wait time');
        box off; grid on;
        %---------
%         %Observer pre-observation panel
%         uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,'Units', 'normal', 'Position',[0,2/3-0.05,2/3,0.3],'style', 'text', 'String','trialStartDelayMin','HorizontalAlignment','right');
%         uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,'Units', 'normal', 'Position',[0,1/3-0.05,2/3,0.3],'style', 'text', 'String','trialStartDelayMax','HorizontalAlignment','right');
%         uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,'Units', 'normal', 'Position',[0,0-0.05,2/3,0.3],'style', 'text', 'String','trialStartDelayLambda','HorizontalAlignment','right');
%         
%         BpodSystem.GUIHandles.ParamEdit.trialStartDelayMin = uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,...
%             'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.trialStartDelayMin);
%         BpodSystem.GUIHandles.ParamEdit.trialStartDelayMax = uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,...
%             'Units', 'normal', 'Position',[2/3+0.025,1/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.trialStartDelayMax);
%         BpodSystem.GUIHandles.ParamEdit.trialStartDelayLambda = uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,...
%             'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.trialStartDelayLambda);
        %---------
        %Observer training panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0,0.5-0.1,0.3,0.5],'style', 'text', 'String','minObsTime','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0,0-0.1,0.3,0.5],'style', 'text', 'String','minObsTimeStep','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0.45,0.5-0.1,0.42,0.5],'style', 'text', 'String',sprintf('obsEarlyPunishLoudness'),'HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0.45,0-0.1,0.42,0.5],'style', 'text', 'String',sprintf('obsEarlyPunishTimeout'),'HorizontalAlignment','right');
        
%         uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0.51,0.75,0.33,0.25],'style', 'text', 'String',sprintf('simulatedMedian\nDemonTrialDur'),'HorizontalAlignment','right');
%         uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0.51,0.5,0.33,0.25],'style', 'text', 'String',sprintf('simulatedCorrect\nRate'),'HorizontalAlignment','right');
%         uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0.51,0.25,0.33,0.25],'style', 'text', 'String',sprintf('simulatedEarly\nWithdrawalRate'),'HorizontalAlignment','right');
%         uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0.51,0,0.33,0.25],'style', 'text', 'String',sprintf('simultaneous\nRewardDelivery'),'HorizontalAlignment','right');
       
        BpodSystem.GUIHandles.ParamEdit.minObsTime = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
            'Units', 'normal', 'Position',[0.31,0.5,0.12,0.5],'style', 'edit', 'String',BpodSystem.ProtocolSettings.minObsTime);
        BpodSystem.GUIHandles.ParamEdit.minObsTimeStep = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
            'Units', 'normal', 'Position',[0.31,0,0.12,0.5],'style', 'edit', 'String',BpodSystem.ProtocolSettings.minObsTimeStep);
        BpodSystem.GUIHandles.ParamEdit.obsEarlyPunishLoudness = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
            'Units', 'normal', 'Position',[0.88,0.5,0.12,0.5],'style', 'edit', 'String',BpodSystem.ProtocolSettings.obsEarlyPunishLoudness);
        BpodSystem.GUIHandles.ParamEdit.obsEarlyPunishTimeout = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
            'Units', 'normal', 'Position',[0.88,0,0.12,0.5],'style', 'edit', 'String',BpodSystem.ProtocolSettings.obsEarlyPunishTimeout);
        
%         BpodSystem.GUIHandles.ParamEdit.simulatedMedianDemonTrialDur = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
%             'Units', 'normal', 'Position',[0.85,0.75,0.15,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.simulatedMedianDemonTrialDur);
%         BpodSystem.GUIHandles.ParamEdit.simulatedCorrectRate = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
%             'Units', 'normal', 'Position',[0.85,0.5,0.15,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.simulatedCorrectRate);
%         BpodSystem.GUIHandles.ParamEdit.simulatedEarlyWithdrawalRate = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
%             'Units', 'normal', 'Position',[0.85,0.25,0.15,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.simulatedEarlyWithdrawalRate);
%         BpodSystem.GUIHandles.ParamEdit.simultaneousRewardDelivery = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
%             'Units', 'normal', 'Position',[0.85,0,0.15,0.25],'style', 'edit', 'String',num2str(BpodSystem.ProtocolSettings.simultaneousRewardDelivery));
%         
        %---------
        %Observer virtual demonstrator panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,'Units', 'normal', 'Position',[0,0.5-0.1,0.87,0.5],'style', 'text', 'String','virtualDemonCorrectRate','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,'Units', 'normal', 'Position',[0,0-0.1,0.87,0.5],'style', 'text', 'String','virtualDemonEarlyWithdrawalRate','HorizontalAlignment','right');      
        
        BpodSystem.GUIHandles.ParamEdit.virtualDemonCorrectRate = uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,...
            'Units', 'normal', 'Position',[0.88,0.5,0.12,0.5],'style', 'edit', 'String',BpodSystem.ProtocolSettings.virtualDemonCorrectRate);
        BpodSystem.GUIHandles.ParamEdit.virtualDemonEarlyWithdrawalRate = uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,...
            'Units', 'normal', 'Position',[0.88,0,0.12,0.5],'style', 'edit', 'String',BpodSystem.ProtocolSettings.virtualDemonEarlyWithdrawalRate);
        %-----------
        %Observer reward panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardParamPanel,'Units', 'normal', 'Position',[0,-0.2,0.74,1],'style', 'text', 'String','obsRewardVolume','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.obsRewardVolume = uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardParamPanel,...
            'Units', 'normal', 'Position',[0.76,0,0.24,1],'style', 'edit', 'String',BpodSystem.ProtocolSettings.obsRewardVolume);
        %----------
        % Observer weight panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsWeightPanel,'Units', 'normal', 'Position',[0,-0.2,0.74,1],'style', 'text', 'String','obsWeight','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.obsWeight = uicontrol('Parent', BpodSystem.GUIHandles.ObsWeightPanel,...
            'Units', 'normal', 'Position',[0.76,0,0.24,1],'style', 'edit', 'String',BpodSystem.ProtocolSettings.obsWeight);
        %----------
        % Observer initiation window panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsInitiationWindowPanel,'Units', 'normal', 'Position',[0,-0.2,0.74,1],'style', 'text', 'String','obsInitiationWindow','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.obsInitiationWindow = uicontrol('Parent', BpodSystem.GUIHandles.ObsInitiationWindowPanel,...
            'Units', 'normal', 'Position',[0.76,0,0.24,1],'style', 'edit', 'String',BpodSystem.ProtocolSettings.obsInitiationWindow);
        
        %---------
        %Observer performance display panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0.75,0.75,0.2],'style', 'text', 'String','Trials done:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0.5,0.75,0.2],'style', 'text', 'String','Completed trials:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0.25,0.75,0.2],'style', 'text', 'String','Withdrew early:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0,0.75,0.2],'style', 'text', 'String','Not harvested:','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.LabelsVal.obsTrialsDone = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0.8,0.75,0.2,0.2],'style', 'text', 'String','0');
        BpodSystem.GUIHandles.LabelsVal.obsCompletedTrials = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0.8,0.5,0.2,0.2],'style', 'text', 'String',num2str(sum(BpodSystem.Data.ObsCompletedTrials)));
        BpodSystem.GUIHandles.LabelsVal.obsEarlyWithdrawals = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0.8,0.25,0.2,0.2],'style', 'text', 'String',num2str(sum(BpodSystem.Data.ObsEarlyWithdrawal)));
        BpodSystem.GUIHandles.LabelsVal.obsNoRewardRetrieved = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0.8,0,0.2,0.2],'style', 'text', 'String',num2str(sum(BpodSystem.Data.ObsDidNotHarvest)));
        %---------
        %Observer reward summary display panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardSummaryPanel,'Units', 'normal', 'Position',[0,-0.1,0.65,1],'style', 'text', 'String','Total reward:','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.LabelsVal.obsRewardAmount = uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardSummaryPanel,'Units', 'normal', 'Position',[0.7,-0.1,0.3,1],'style', 'text', 'String',num2str(BpodSystem.Data.ObsRewardAmount));
        
        
        %Set the font size on the figure here
        fontScaling = BpodSystem.GUIHandles.LabelsVal.obsTrialsDone.FontSize;
        set(findall(BpodSystem.GUIHandles.Figures.ObsFigure,'-property','FontSize'),'FontSize',fontScaling) %do the scaling

        %--------------------------------------------------------------------------
        %%
    case 'refresh'
        BpodSystem.GUIHandles.LabelsVal.obsTrialsDone.String = num2str(length(BpodSystem.Data.ObsOutcomeRecord));
        BpodSystem.GUIHandles.LabelsVal.obsCompletedTrials.String = num2str(sum(BpodSystem.Data.ObsCompletedTrials));
        BpodSystem.GUIHandles.LabelsVal.obsEarlyWithdrawals.String = num2str(sum(BpodSystem.Data.ObsEarlyWithdrawal));
        BpodSystem.GUIHandles.LabelsVal.obsNoRewardRetrieved.String = num2str(sum(BpodSystem.Data.ObsDidNotHarvest));
        
        BpodSystem.GUIHandles.LabelsVal.obsRewardAmount.String = num2str(sum(BpodSystem.Data.ObsRewardAmount));
        %%
    case 'close'
        %simply close the figure
        close(BpodSystem.GUIHandles.Figures.ObsFigure)
end

% %Set the font size on the figure
% fontScaling = BpodSystem.GUIHandles.LabelsVal.obsTrialsDone.FontSize;
% set(findall(BpodSystem.GUIHandles.Figures.ObsFigure,'-property','FontSize'),'FontSize',fontScaling) %do the scaling

end