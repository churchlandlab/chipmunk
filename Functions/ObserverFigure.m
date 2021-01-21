function ObserverFigure(figMethod)
% ObserverFigure('init') %Generates the data display and UIcontrols for the
% observer mouse
% ObserverFIgure('close') %Closes the figure created with the init call
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
        BpodSystem.GUIHandles.Figures.ObsFigure = figure('Units','Normal','Position',[0, 0.06, 0.499, 0.45],...
            'Name',[BpodSystem.ProtocolSettings.experimentName ' - ' BpodSystem.ProtocolSettings.obsID ' - Observer'],...
            'NumberTitle','off','MenuBar','none');
        
        %Place the panels and axes on the figure
        BpodSystem.GUIHandles.ObsPreObsPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.05, 0.05, 0.225, 0.26],'Title','Pre observing','FontWeight','bold');
        BpodSystem.GUIHandles.ObsTrainPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.275, 0.05, 0.225, 0.26],'Title','Observer fixation training','FontWeight','bold');
        BpodSystem.GUIHandles.ObsVirtualDemonPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.5, 0.05, 0.225, 0.26],'Title','Virtual demonstrator','FontWeight','bold');
        BpodSystem.GUIHandles.ObsRewardParamPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.725, 0.19, 0.225, 0.12],'Title','Reward parameters','FontWeight','bold');
        BpodSystem.GUIHandles.ObsWeightPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.725, 0.05, 0.225, 0.12],'Title','Observer weight','FontWeight','bold');
        
        BpodSystem.GUIHandles.ObsPerformancePanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.725, 0.64, 0.25, 0.3],'Title','Performance summary','FontWeight','bold');
        BpodSystem.GUIHandles.ObsRewardSummaryPanel = uipanel('Parent', BpodSystem.GUIHandles.Figures.ObsFigure, 'Units', 'Normal',...
            'Position', [0.725, 0.53, 0.25, 0.11],'Title','Reward summary','FontWeight','bold');
        
        BpodSystem.GUIHandles.InterTiralInterval = axes('Parent', BpodSystem.GUIHandles.Figures.ObsFigure,...
            'Units', 'Normal', 'Position', [0.075, 0.53, 0.375, 0.4],'tickdir','out','NextPlot','add');
        xlabel('Trial number'); ylabel('Interval between trial initiations (s)'); title('Inter trial intervals');
        box off;
        BpodSystem.GUIHandles.ObsTimeDistribution = axes('Parent', BpodSystem.GUIHandles.Figures.ObsFigure,...
            'Units', 'Normal', 'Position', [0.525, 0.53, 0.175, 0.4],'tickdir','out','NextPlot', 'add');
        xlabel('Estimated count'); ylabel('Wait times (s)'); title('Obs wait time distrib');
        box off; grid on;
        %---------
        %Observer pre-observation panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,'Units', 'normal', 'Position',[0,2/3-0.05,2/3,0.3],'style', 'text', 'String','trialStartDelayMin','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,'Units', 'normal', 'Position',[0,1/3-0.05,2/3,0.3],'style', 'text', 'String','trialStartDelayMax','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,'Units', 'normal', 'Position',[0,0-0.05,2/3,0.3],'style', 'text', 'String','trialStartDelayLambda','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.trialStartDelayMin = uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.trialStartDelayMin);
        BpodSystem.GUIHandles.ParamEdit.trialStartDelayMax = uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,1/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.trialStartDelayMax);
        BpodSystem.GUIHandles.ParamEdit.trialStartDelayLambda = uicontrol('Parent', BpodSystem.GUIHandles.ObsPreObsPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.trialStartDelayLambda);
        %---------
        %Observer training panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0,2/3-0.05,2/3,0.3],'style', 'text', 'String','minObsTime','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,'Units', 'normal', 'Position',[0,1/3-0.05,2/3,0.3],'style', 'text', 'String','minObsTimeStep','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.minObsTime = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.minObsTime);
        BpodSystem.GUIHandles.ParamEdit.minObsTimeStep = uicontrol('Parent', BpodSystem.GUIHandles.ObsTrainPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,1/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.minObsTimeStep);
        %---------
        %Observer virtual demonstrator panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,'Units', 'normal', 'Position',[0,2/3-0.05,2/3,0.3],'style', 'text', 'String','virtTrialDurMin','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,'Units', 'normal', 'Position',[0,1/3-0.05,2/3,0.3],'style', 'text', 'String','virtTrialDurMax','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,'Units', 'normal', 'Position',[0,0-0.05,2/3,0.3],'style', 'text', 'String','virtTrialDurLambda','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.virtTrialsDurMin = uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.virtTrialDurMin);
        BpodSystem.GUIHandles.ParamEdit.virtTrialsDurMax = uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,1/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.virtTrialDurMax);
        BpodSystem.GUIHandles.ParamEdit.virtTrialsDurLambda = uicontrol('Parent', BpodSystem.GUIHandles.ObsVirtualDemonPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.virtTrialDurLambda);
        %-----------
        %Observer reward panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardParamPanel,'Units', 'normal', 'Position',[0,-0.2,2/3,1],'style', 'text', 'String','obsRewardVolume','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.obsRewardVolume = uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardParamPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1],'style', 'edit', 'String',BpodSystem.ProtocolSettings.obsRewardVolume);
        %----------
        % Observer weight panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsWeightPanel,'Units', 'normal', 'Position',[0,-0.2,2/3,1],'style', 'text', 'String','obsWeight','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.obsWeight = uicontrol('Parent', BpodSystem.GUIHandles.ObsWeightPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1],'style', 'edit', 'String',BpodSystem.ProtocolSettings.obsWeight);
        %---------
        %Observer performance display panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0.75,2/3,0.2],'style', 'text', 'String','Trials done:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0.5,2/3,0.2],'style', 'text', 'String','Completed trials:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0.25,2/3,0.2],'style', 'text', 'String','Early withdrawals:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[0,0,2/3,0.2],'style', 'text', 'String','No reward retrieved:','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.LabelsVal.obsTrialsDone = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[2/3,0.75,1/3,0.2],'style', 'text', 'String','0');
        BpodSystem.GUIHandles.LabelsVal.obsCompletedTrials = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[2/3,0.5,1/3,0.2],'style', 'text', 'String','0');
        BpodSystem.GUIHandles.LabelsVal.obsEarlyWithdrawals = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[2/3,0.25,1/3,0.2],'style', 'text', 'String','0');
        BpodSystem.GUIHandles.LabelsVal.obsNoRewardRetrieved = uicontrol('Parent', BpodSystem.GUIHandles.ObsPerformancePanel,'Units', 'normal', 'Position',[2/3,0,1/3,0.2],'style', 'text', 'String','0');
        %---------
        %Observer reward summary display panel
        uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardSummaryPanel,'Units', 'normal', 'Position',[0,-0.1,2/3,1],'style', 'text', 'String','Total reward:','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.LabelsVal.obsReward = uicontrol('Parent', BpodSystem.GUIHandles.ObsRewardSummaryPanel,'Units', 'normal', 'Position',[2/3,-0.1,1/3,1],'style', 'text', 'String','0');
        
        %--------------------------------------------------------------------------
        %%
    case 'close'
        %simply close the figure
        close(BpodSystem.GUIHandles.Figures.ObsFigure)
end

%Set the font size on the figure
screenParam = get(0,'screensize'); %retrieve info about the pixels
fontScaling = screenParam(4)*(8.8/720); %determine Font size based on the height of the screen and a ratio tested before
set(findall(BpodSystem.GUIHandles.Figures.ObsFigure,'-property','FontSize'),'FontSize',fontScaling) %do the scaling

end