function varargout = DemonstratorFigure(varargin)
% DemonstratorFigure('init') %Creates a figure including all the display
% %items, UIcontrols and axes.
% paramStruct = DemonstratorFigure('update', paramStruct) %Retrieves the
% %the user inputs (also observer!) after the the start/update button has
% %been clicked and inserts them into the paramStruct.
% DemonstratorFigure('refresh', paramStruct) %Refreshes the display of automatically
% %changing but also changable values (for instance minWaitTime).
% DemonstratorFigure('close') %Simply close the figure
%
% INPUTS: -figMethod: The method for creation/updating of the figure
%         -paramStruct: Struct containing the experiment parameters
%
% OUTPUTS: -paramStruct: Updated experiment parameters
%
% Make sure to run the update and refresh after the plotting so it can
% scale the font on plots and display equally!
%
% Based on BpodParameterGUI_Visual, LO 1/12/21
%--------------------------------------------------------------------------


global BpodSystem
figMethod = varargin{1}; %the figure method
if nargin > 1
    paramStruct = varargin{2}; %Store the structure holding the parameters
end

switch figMethod
    %% Initialize the figure
    case 'init'
        %Generate an 780 * 650 pixels figure and postion it in he top right
        %corner
        screenParam = get(0,'screensize');
        
        BpodSystem.GUIHandles.Figures.DemonFigure = figure('Units','Pixels','Position',[screenParam(3)-800, screenParam(4)-705, 780, 650],...
            'Name',[BpodSystem.ProtocolSettings.experimentName ' - ' BpodSystem.ProtocolSettings.demonID ' - Demonstrator'],...
            'NumberTitle','off','MenuBar','none');
        
        %Erase prior parameter edits to be able to switch from observer to
        %demonstrator tasks.
        BpodSystem.GUIHandles.ParamEdit = [];
        
        %Create the tab structure on the figure
        BpodSystem.GUIHandles.DemonFigTabs = uitabgroup('Parent', BpodSystem.GUIHandles.Figures.DemonFigure, 'TabLocation', 'left');
        BpodSystem.GUIHandles.DemonTabGroup.StimPerform = uitab('Parent', BpodSystem.GUIHandles.DemonFigTabs, 'Title', 'Stimuli & performance');
        BpodSystem.GUIHandles.DemonTabGroup.TaskControl = uitab('Parent', BpodSystem.GUIHandles.DemonFigTabs, 'Title', 'Task control');
        BpodSystem.GUIHandles.DemonTabGroup.Reward = uitab('Parent', BpodSystem.GUIHandles.DemonFigTabs, 'Title', 'Reward');
        BpodSystem.GUIHandles.DemonTabGroup.ExtDev = uitab('Parent', BpodSystem.GUIHandles.DemonFigTabs, 'Title', 'External devices');
        BpodSystem.GUIHandles.DemonTabGroup.MetaData = uitab('Parent', BpodSystem.GUIHandles.DemonFigTabs, 'Title', 'Display & metadata');
        
        %-------------------------------------------------------------------------
        %Start with the the stimulus and performance tab
        
        %Panels and axes for display and manipulation on Stim tab
        BpodSystem.GUIHandles.DemonChoicePanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform, 'Units', 'Normal',...
            'Position', [0.65, 0.08, 0.3, 0.16],'Title','Choice parameters','FontWeight','bold');
        BpodSystem.GUIHandles.DemonStimPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform, 'Units', 'Normal',...
            'Position', [0.05, 0.0, 0.6, 0.24],'Title','Stimulus parameters','FontWeight','bold');
        BpodSystem.GUIHandles.DemonUpdatePanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform, 'Units', 'Normal',...
            'Position', [0.65, 0, 0.3, 0.08]);
        
        BpodSystem.GUIHandles.PerformanceSummaryPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform, 'Units', 'Normal',...
            'Position', [0.65, 0.31, 0.3, 0.21],'Title','Performance summary','FontWeight','bold');
        
        BpodSystem.GUIHandles.PsychometricPlotDemonstrator = axes('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform,...
            'Units', 'Normal', 'Position', [0.1, 0.31, 0.2, 0.2],'tickdir','out','NextPlot','add'); %NextPlot -> make sure to keep the settings
        xlabel('Stim frequency (Hz)'); ylabel('Prop right side choices'); title('Psychometric plot');
        box off; grid on;
        BpodSystem.GUIHandles.WaitTimeDiffPlotDemonstrator = axes('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform,...
            'Units', 'Normal', 'Position', [0.4, 0.31, 0.2, 0.2],'tickdir','out', 'NextPlot','add');
        xlabel('Density estimate'); ylabel('Wait time difference (s)'); title('Fixation time diff');
        box off; grid on;
        BpodSystem.GUIHandles.PerformancePlotDemonstrator = axes('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform,...
            'Units', 'Normal', 'Position', [0.1, 0.604, 0.85, 0.11],'tickdir','out','NextPlot','add');
        xlabel('Trial number'); ylabel('Fraction correct'); title('Performance plot');
        box off; grid on;
        BpodSystem.GUIHandles.OutcomePlotDemonstrator = axes('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform,...
            'Units', 'Normal', 'Position', [0.1, 0.805, 0.85, 0.065],'tickdir','out','NextPlot','add');
        xlabel('Trial number'); title('Outcome plot');
        box off;
        BpodSystem.GUIHandles.StimulusPlotA = axes('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform,...
            'Units', 'Normal', 'Position', [0.53, 0.9, 0.42, 0.05],'xtick',[],'ytick',[],'NextPlot','add');
        title('Auditory stimuli')
        BpodSystem.GUIHandles.StimulusPlotV = axes('Parent', BpodSystem.GUIHandles.DemonTabGroup.StimPerform,...
            'Units', 'Normal', 'Position', [0.1, 0.9, 0.42, 0.05],'xtick',[],'ytick',[],'NextPlot','add');
        title('Visual stimuli')
        
        %------------
        %Fill in the UIcontrols for display and manipulation
        
        %Choice panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,'Units', 'normal', 'Position',[0,0.75-0.03,2/3,0.25],'style', 'text', 'String','highRateSide', 'HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,'Units', 'normal', 'Position',[0,0.5-0.03,2/3,0.25],'style', 'text', 'String','propLeft','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,'Units', 'normal', 'Position',[0,0.25-0.03,2/3,0.25],'style', 'text', 'String','antiBiasStrength','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,'Units', 'normal', 'Position',[0,0-0.03,2/3,0.25],'style', 'text', 'String','antiBiasTau','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.highRateSide = uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,...
            'Units', 'normal', 'Position',[2/3+0.05,0.75,1/3-0.05,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.highRateSide);
        BpodSystem.GUIHandles.ParamEdit.propLeft = uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,...
            'Units', 'normal', 'Position',[2/3+0.05,0.5,1/3-0.05,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.propLeft);
        BpodSystem.GUIHandles.ParamEdit.antiBiasStrength = uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,...
            'Units', 'normal', 'Position',[2/3+0.05,0.25,1/3-0.05,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.antiBiasStrength);
        BpodSystem.GUIHandles.ParamEdit.antiBiasTau = uicontrol('Parent', BpodSystem.GUIHandles.DemonChoicePanel,...
            'Units', 'normal', 'Position',[2/3+0.05,0,1/3-0.05,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.antiBiasTau);
        %----
        %Stimulus panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[0,5/6,2/6,1/6],'style', 'text', 'String','visEventRateList','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[0,4/6,2/6,1/6],'style', 'text', 'String','audEventRateList','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[0,3/6,2/6,1/6],'style', 'text', 'String','multEventRateList','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[0,2/6,2/6,1/6],'style', 'text', 'String','propOnlyVisual','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[3/6,2/6,2/6,1/6],'style', 'text', 'String','propOnlyAuditory','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[0,1/6,2/6,1/6],'style', 'text', 'String','stimBrightness','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[3/6,1/6,2/6,1/6],'style', 'text', 'String','stimLoudness','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[0,0,2/6,1/6],'style', 'text', 'String','syncMultiSensory','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,'Units', 'normal', 'Position',[3/6,0,2/6,1/6],'style', 'text', 'String','isPoissonStim','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.visEventRateList = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,5/6,4/6-0.025,1/6],'style', 'edit', 'String',num2str(BpodSystem.ProtocolSettings.visEventRateList));
        BpodSystem.GUIHandles.ParamEdit.audEventRateList = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,4/6,4/6-0.025,1/6],'style', 'edit', 'String',num2str(BpodSystem.ProtocolSettings.audEventRateList));
        BpodSystem.GUIHandles.ParamEdit.multEventRateList = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,3/6,4/6-0.025,1/6],'style', 'edit', 'String',num2str(BpodSystem.ProtocolSettings.multEventRateList));
        BpodSystem.GUIHandles.ParamEdit.propOnlyVisual = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,2/6,1/6-0.025,1/6],'style', 'edit', 'String',BpodSystem.ProtocolSettings.propOnlyVisual);
        BpodSystem.GUIHandles.ParamEdit.propOnlyAuditory = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[5/6+0.025,2/6,1/6-0.025,1/6],'style', 'edit', 'String',BpodSystem.ProtocolSettings.propOnlyAuditory);
        BpodSystem.GUIHandles.ParamEdit.stimBrightness = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,1/6,1/6-0.025,1/6],'style', 'edit', 'String',BpodSystem.ProtocolSettings.stimBrightness);
        BpodSystem.GUIHandles.ParamEdit.stimLoudness = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[5/6+0.025,1/6,1/6-0.025,1/6],'style', 'edit', 'String',BpodSystem.ProtocolSettings.stimLoudness);
        BpodSystem.GUIHandles.ParamEdit.syncMultiSensory = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,0,1/6-0.025,1/6],'style', 'edit', 'String',BpodSystem.ProtocolSettings.syncMultiSensory);
        BpodSystem.GUIHandles.ParamEdit.isPoissonStim = uicontrol('Parent', BpodSystem.GUIHandles.DemonStimPanel,...
            'Units', 'normal', 'Position',[5/6+0.025,0,1/6-0.025,1/6],'style', 'edit', 'String',BpodSystem.ProtocolSettings.isPoissonStim);
        %---
        %Save and Start/Update panel
        BpodSystem.GUIHandles.DemonSaveButton = uicontrol('Parent', BpodSystem.GUIHandles.DemonUpdatePanel,...
            'Units', 'normal', 'Position', [0,0.1,0.5,0.8],'Style','pushbutton','String','Save settings',...
            'Callback',{@saveButton});
        BpodSystem.GUIHandles.DemonStartButton = uicontrol('Parent', BpodSystem.GUIHandles.DemonUpdatePanel,...
            'Units', 'normal', 'Position', [0.5,0.1,0.5,0.8],'Style','pushbutton','String','Start',...
            'Callback',{@startButton});
        %----
        %Summary display panel
        uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[0.05,0.75,2/3,0.2],'style', 'text', 'String','Trials done:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[0.05,0.55,2/3,0.2],'style', 'text', 'String','Completed trials:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[0.05,0.35,2/3,0.2],'style', 'text', 'String','Correct trials:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[0.05,0.15,2/3,0.2],'style', 'text', 'String','Early withdrawals:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[0.05,-0.05,2/3,0.2],'style', 'text', 'String','No choice trials:','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.LabelsVal.trialsDone = uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,0.75,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        BpodSystem.GUIHandles.LabelsVal.completedTrials = uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,0.55,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        BpodSystem.GUIHandles.LabelsVal.correctTrials = uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,0.35,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        BpodSystem.GUIHandles.LabelsVal.earlyWithdrawals = uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,0.15,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        BpodSystem.GUIHandles.LabelsVal.noChoiceTrials = uicontrol('Parent', BpodSystem.GUIHandles.PerformanceSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,-0.05,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        
        %--------------------------------------------------------------------------
        %Now assemble the task control tab
        
        %Here first the state logic plot
        BpodSystem.GUIHandles.StateLogic = axes('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl,...
            'Units', 'Normal', 'Position', [0.05, 0.45, 0.9, 0.5],'NextPlot','add');
        BpodSystem.GUIHandles.StateLogic.XAxis.Visible = 'off';BpodSystem.GUIHandles.StateLogic.YAxis.Visible = 'off';
        title(BpodSystem.ProtocolSettings.smaAssembler)
        
        %Set the different Task control panels
        BpodSystem.GUIHandles.DemonExperimentPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl, 'Units', 'Normal',...
            'Position', [0.05, 0.32, 0.3, 0.12],'Title','Experiment','FontWeight','bold');
         BpodSystem.GUIHandles.DemonInitiationPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl, 'Units', 'Normal',...
            'Position', [0.35, 0.32, 0.3, 0.12],'Title','Demonstrator initiation','FontWeight','bold');
        BpodSystem.GUIHandles.DemonFixationPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl, 'Units', 'Normal',...
            'Position', [0.35, 0.2, 0.3, 0.12],'Title','Fixation','FontWeight','bold');
        BpodSystem.GUIHandles.DemonPreStimPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl, 'Units', 'Normal',...
            'Position', [0.05, 0.2, 0.3, 0.12],'Title','Pre stimulus','FontWeight','bold');
        BpodSystem.GUIHandles.DemonInterTrialPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl, 'Units', 'Normal',...
            'Position', [0.65, 0.2, 0.3, 0.12],'Title','Inter trial','FontWeight','bold');
        BpodSystem.GUIHandles.DemonPostStimPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl, 'Units', 'Normal',...
            'Position', [0.65, 0.04, 0.3, 0.16],'Title','Post stimulus','FontWeight','bold');
        BpodSystem.GUIHandles.DemonPunishPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.TaskControl, 'Units', 'Normal',...
            'Position', [0.05, 0.04, 0.6, 0.16],'Title','Punishment','FontWeight','bold');
        %---
        %Experiment panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonExperimentPanel,'Units', 'normal', 'Position',[0,2/3-0.05,1,1/3],'style', 'text', 'String',BpodSystem.ProtocolSettings.experimentName);
        
        BpodSystem.GUIHandles.DemonChangeExpButton = uicontrol('Parent', BpodSystem.GUIHandles.DemonExperimentPanel,...
            'Units', 'normal', 'Position', [0.1,0.1,0.8,0.4],'Style','pushbutton','String','Change experiment',...
            'Callback',{@changeExpButton});
        %-----
        %Initiation panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonInitiationPanel,'Units', 'normal', 'Position',[0,2/3,2/3,1/3],'style', 'text', 'String','initiationWindow','HorizontalAlignment','right');

        BpodSystem.GUIHandles.ParamEdit.initiationWindow = uicontrol('Parent', BpodSystem.GUIHandles.DemonInitiationPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.initiationWindow);
        
        %------
        %Fixation panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonFixationPanel,'Units', 'normal', 'Position',[0,2/3,2/3,1/3],'style', 'text', 'String','minWaitTime','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonFixationPanel,'Units', 'normal', 'Position',[0,1/3,2/3,1/3],'style', 'text', 'String','minWaitTimeStep','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonFixationPanel,'Units', 'normal', 'Position',[0,0,2/3,1/3],'style', 'text', 'String','goCueLoudness','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.minWaitTime = uicontrol('Parent', BpodSystem.GUIHandles.DemonFixationPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.minWaitTime);
        BpodSystem.GUIHandles.ParamEdit.minWaitTimeStep = uicontrol('Parent', BpodSystem.GUIHandles.DemonFixationPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,1/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.minWaitTimeStep);
        BpodSystem.GUIHandles.ParamEdit.goCueLoudness = uicontrol('Parent', BpodSystem.GUIHandles.DemonFixationPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.goCueLoudness);
        %------------
        %Pre stim panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPreStimPanel,'Units', 'normal', 'Position',[0,2/3,2/3,1/3],'style', 'text', 'String','preStimDelayMin','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPreStimPanel,'Units', 'normal', 'Position',[0,1/3,2/3,1/3],'style', 'text', 'String','preStimDelayMax','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPreStimPanel,'Units', 'normal', 'Position',[0,0,2/3,1/3],'style', 'text', 'String','preStimDelayLambda','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.preStimDelayMin = uicontrol('Parent', BpodSystem.GUIHandles.DemonPreStimPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.preStimDelayMin);
        BpodSystem.GUIHandles.ParamEdit.preStimDelayMax = uicontrol('Parent', BpodSystem.GUIHandles.DemonPreStimPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,1/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.preStimDelayMax);
        BpodSystem.GUIHandles.ParamEdit.preStimDelayLambda = uicontrol('Parent', BpodSystem.GUIHandles.DemonPreStimPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.preStimDelayLambda);
        %---------
        %Inter trial panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonInterTrialPanel,'Units', 'normal', 'Position',[0,2/3,2/3,1/3],'style', 'text', 'String','interTrialDurMin','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonInterTrialPanel,'Units', 'normal', 'Position',[0,1/3,2/3,1/3],'style', 'text', 'String','interTrialDurMax','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonInterTrialPanel,'Units', 'normal', 'Position',[0,0,2/3,1/3],'style', 'text', 'String','interTrialDurLambda','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.interTrialDurMin = uicontrol('Parent', BpodSystem.GUIHandles.DemonInterTrialPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,2/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.interTrialDurMin);
        BpodSystem.GUIHandles.ParamEdit.interTrialDurMax = uicontrol('Parent', BpodSystem.GUIHandles.DemonInterTrialPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,1/3,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.interTrialDurMax);
        BpodSystem.GUIHandles.ParamEdit.interTrialDurLambda = uicontrol('Parent', BpodSystem.GUIHandles.DemonInterTrialPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,1/3],'style', 'edit', 'String',BpodSystem.ProtocolSettings.interTrialDurLambda);
        %---------
        %Post stimulation panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,'Units', 'normal', 'Position',[0,0.75-0.02,2/3,0.2],'style', 'text', 'String','extraStimDur','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,'Units', 'normal', 'Position',[0,0.5-0.02,2/3,0.2],'style', 'text', 'String','extraStimDurStep','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,'Units', 'normal', 'Position',[0,0.25-0.02,2/3,0.2],'style', 'text', 'String','timeToChoose','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,'Units', 'normal', 'Position',[0,0-0.02,2/3,0.2],'style', 'text', 'String','noChoiceTimeout','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.extraStimDur = uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.75,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.extraStimDur);
        BpodSystem.GUIHandles.ParamEdit.extraStimDurStep = uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.5,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.extraStimDurStep);
        BpodSystem.GUIHandles.ParamEdit.timeToChoose = uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.25,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.timeToChoose);
        BpodSystem.GUIHandles.ParamEdit.noChoiceTimeout = uicontrol('Parent', BpodSystem.GUIHandles.DemonPostStimPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.noChoiceTimeout);
        %--------
        %Punishment panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,'Units', 'normal', 'Position',[0,0.75-0.02,2/6,0.2],'style', 'text', 'String','wrongPunishType','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,'Units', 'normal', 'Position',[0,0.5-0.02,2/6,0.2],'style', 'text', 'String','wrongPunishLoudness','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,'Units', 'normal', 'Position',[0,0.25-0.02,2/6,0.2],'style', 'text', 'String','wrongPunishTimeout','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,'Units', 'normal', 'Position',[3/6,0.75-0.02,2/6,0.2],'style', 'text', 'String','earlyPunishType','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,'Units', 'normal', 'Position',[3/6,0.5-0.02,2/6,0.2],'style', 'text', 'String','earlyPunishLoudness','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,'Units', 'normal', 'Position',[3/6,0.25-0.02,2/6,0.2],'style', 'text', 'String','earlyPunishTimeout','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.wrongPunishType = uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,0.75,1/6-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.wrongPunishType);
        BpodSystem.GUIHandles.ParamEdit.wrongPunishLoudness = uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,0.5,1/6-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.wrongPunishLoudness);
        BpodSystem.GUIHandles.ParamEdit.wrongPunishTimeout = uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,...
            'Units', 'normal', 'Position',[2/6+0.025,0.25,1/6-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.wrongPunishTimeout);
        BpodSystem.GUIHandles.ParamEdit.earlyPunishType = uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,...
            'Units', 'normal', 'Position',[5/6+0.025,0.75,1/6-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.earlyPunishType);
        BpodSystem.GUIHandles.ParamEdit.earlyPunishLoudness = uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,...
            'Units', 'normal', 'Position',[5/6+0.025,0.5,1/6-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.earlyPunishLoudness);
        BpodSystem.GUIHandles.ParamEdit.earlyPunishTimeout = uicontrol('Parent', BpodSystem.GUIHandles.DemonPunishPanel,...
            'Units', 'normal', 'Position',[5/6+0.025,0.25,1/6-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.earlyPunishTimeout);
        
        %--------------------------------------------------------------------------
        %Set up the reward tab
        
        %Initialize the reward and body weight panels
        BpodSystem.GUIHandles.DemonRewardSummaryPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.Reward, 'Units', 'Normal',...
            'Position', [0.05, 0.8, 0.3, 0.16],'Title','Reward summary','FontWeight','bold');
        BpodSystem.GUIHandles.DemonRewardParamPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.Reward, 'Units', 'Normal',...
            'Position', [0.05, 0.5, 0.3, 0.16],'Title','Reward parameters','FontWeight','bold');
        BpodSystem.GUIHandles.DemonWeightPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.Reward, 'Units', 'Normal',...
            'Position', [0.35, 0.5, 0.3, 0.16],'Title','Demonstrator weight','FontWeight','bold');
        %--------
        %Reward parameter panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardParamPanel,'Units', 'normal', 'Position',[0,0.75,2/3,0.2],'style', 'text', 'String','leftRewardVolume','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardParamPanel,'Units', 'normal', 'Position',[0,0.5,2/3,0.2],'style', 'text', 'String','rightRewardVolume','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.leftRewardVolume = uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardParamPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.75,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.leftRewardVolume);
        BpodSystem.GUIHandles.ParamEdit.rightRewardVolume = uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardParamPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.5,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.rightRewardVolume);
        %------
        %Reward summary panel
        uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardSummaryPanel,'Units', 'normal', 'Position',[0,0.75,2/3,0.2],'style', 'text', 'String','Left side reward:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardSummaryPanel,'Units', 'normal', 'Position',[0,0.5,2/3,0.2],'style', 'text', 'String','Right side reward:','HorizontalAlignment','right');
        uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardSummaryPanel,'Units', 'normal', 'Position',[0,0.25,2/3,0.2],'style', 'text', 'String','Total reward:','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.LabelsVal.leftSideReward = uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,0.75,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        BpodSystem.GUIHandles.LabelsVal.rightSideReward = uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,0.5,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        BpodSystem.GUIHandles.LabelsVal.totalReward = uicontrol('Parent', BpodSystem.GUIHandles.DemonRewardSummaryPanel,'Units', 'normal', 'Position',[2/3+0.1,0.25,1/3-0.1,0.2],'style', 'text', 'String','0','HorizontalAlignment','left');
        %------
        %Demonstrator body weight
        uicontrol('Parent', BpodSystem.GUIHandles.DemonWeightPanel,'Units', 'normal', 'Position',[0,0.75,2/3,0.2],'style', 'text', 'String','demonWeight','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.demonWeight = uicontrol('Parent', BpodSystem.GUIHandles.DemonWeightPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.75,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.demonWeight);
        
        %--------------------------------------------------------------------------
        %Do the external device tab
        
        %Initialize panels
        BpodSystem.GUIHandles.LabcamsPanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.ExtDev, 'Units', 'Normal',...
            'Position', [0.05, 0.8, 0.3, 0.16],'Title','Labcams','FontWeight','bold');
        BpodSystem.GUIHandles.MiniscopePanel = uipanel('Parent', BpodSystem.GUIHandles.DemonTabGroup.ExtDev, 'Units', 'Normal',...
            'Position', [0.35, 0.8, 0.3, 0.16],'Title','Miniscope','FontWeight','bold');
        %---------
        %Labcams panel
        uicontrol('Parent', BpodSystem.GUIHandles.LabcamsPanel,'Units', 'normal', 'Position',[0,0.75,2/3,0.2],'style', 'text', 'String','labcamsAddress','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.labcamsAddress = uicontrol('Parent', BpodSystem.GUIHandles.LabcamsPanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.75,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.labcamsAddress);
        %---------
        %Miniscope panel
        uicontrol('Parent', BpodSystem.GUIHandles.MiniscopePanel,'Units', 'normal', 'Position',[0,0.75,2/3,0.2],'style', 'text', 'String','miniscopeID','HorizontalAlignment','right');
        
        BpodSystem.GUIHandles.ParamEdit.miniscopeID = uicontrol('Parent', BpodSystem.GUIHandles.MiniscopePanel,...
            'Units', 'normal', 'Position',[2/3+0.025,0.75,1/3-0.025,0.25],'style', 'edit', 'String',BpodSystem.ProtocolSettings.miniscopeID);
        
        %------------------------------------------------------------------
        
        %%
    case 'update'
        %Update the settingsStruct for observer and demonstrator according
        %to the user inputs
        
        %Get field names of the fields linked to a UIcontrol
        paramNames = fieldnames(BpodSystem.GUIHandles.ParamEdit);
        for k=1:length(paramNames)
            temp = []; %initialize a temporary variable to hold the UIstring
            eval(['temp = get(BpodSystem.GUIHandles.ParamEdit.' paramNames{k} ', ''String'');']); %Retrieve the string inside the UIcontrol edit box
            if ~isempty(str2num(num2str(temp))) %This is a nice test of whether there are only numbers or whether there are letters too
                eval(['paramStruct.' paramNames{k} ' = str2num(temp);']);
            else
                eval(['paramStruct.' paramNames{k} ' = temp;']);
            end
        end
        BpodSystem.ProtocolSettings = paramStruct; %Sync Bpod with the external settings
        varargout{1} = paramStruct; %Output the changed parameter struct
        %--------------------------------------------------------------------------
        
        %%
    case 'refresh'
        %Adapt the display value of the editable UIcontrols according to
        %automatic updates, e.g. minWaitTime changes, etc.
        
        if ~isequal(paramStruct, BpodSystem.ProtocolSettings) %check whether something has been changed in the parameters
            %Get field names of the fields linked to a UIcontrol
            paramNames = fieldnames(BpodSystem.GUIHandles.ParamEdit);
            for k=1:length(paramNames) %directly set the display to the input values from
               if eval(['paramStruct.' paramNames{k} ' ~= BpodSystem.ProtocolSettings.' paramNames{k}]) %only change the display of items that need it
                    eval(['set(BpodSystem.GUIHandles.ParamEdit.' paramNames{k} ', ''String'', num2str(paramStruct.' paramNames{k} '));'])
                end
            end
            BpodSystem.ProtocolSettings = paramStruct; %conclude by syncing the two
        end
        
        %Update also the display of the display UI controls for trial
        %parameters to keep this all together...
        BpodSystem.GUIHandles.LabelsVal.trialsDone.String = num2str(length(BpodSystem.Data.OutcomeRecord));
        BpodSystem.GUIHandles.LabelsVal.completedTrials.String = num2str(sum(BpodSystem.Data.ValidTrials));
        BpodSystem.GUIHandles.LabelsVal.correctTrials.String = num2str(sum(BpodSystem.Data.CorrectResponse));
        BpodSystem.GUIHandles.LabelsVal.earlyWithdrawals.String = num2str(sum(BpodSystem.Data.EarlyWithdrawal));
        BpodSystem.GUIHandles.LabelsVal.noChoiceTrials.String = num2str(sum(BpodSystem.Data.DidNotChoose));
        
        BpodSystem.GUIHandles.LabelsVal.leftSideReward.String = num2str(BpodSystem.Data.LeftSideRewardAmount);
        BpodSystem.GUIHandles.LabelsVal.rightSideReward.String = num2str(BpodSystem.Data.RightSideRewardAmount);
        BpodSystem.GUIHandles.LabelsVal.totalReward.String = num2str(BpodSystem.Data.LeftSideRewardAmount + BpodSystem.Data.RightSideRewardAmount);
        %------------------------------------------------------------------
        
        %%
    case 'close'
        %Close the figure at the end of the experiment
        close(BpodSystem.GUIHandles.Figures.DemonFigure)
end

%---------------------------------------------------------------------
%Finally adjust the font size on the entire figure

%Set the font size on the figure
% screenParam = get(0,'screensize'); %retrieve info about the pixels
% fontScaling = screenParam(4)*(8.8/720); %determine Font size based on the height of the screen and a ratio tested before
% set(findall(BpodSystem.GUIHandles.Figures.DemonFigure,'-property','FontSize'),'FontSize',fontScaling) %do the scaling

end

function startButton (h, ev) %this callback delays the evaluation of the inputs until the next trial is started and sets update to true
global update
update = 1; %Make sure to enter into update mode when the function is called the next time
global BpodSystem
uiresume(BpodSystem.GUIHandles.Figures.DemonFigure); %wait for spout control and clear handle afterwards %???
set(h,'String','Update settings'); %Change the button
end

function saveButton(h, ev) %Take a snapshot of the current settings and save them. Also set the update variable to 1, so that the settings are updated in the next round
global BpodSystem
global update

ProtocolSettings = BpodSystem.ProtocolSettings; %Take the params from the BpodSystem here, so that changes can be saved even if the paramStruct is not passed as an input
%Get field names of the fields linked to a UIcontrol
paramNames = fieldnames(BpodSystem.GUIHandles.ParamEdit);
for k=1:length(paramNames)
    temp = []; %initialize a temporary variable to hold the UIstring
    eval(['temp = get(BpodSystem.GUIHandles.ParamEdit.' paramNames{k} ', ''String'');']); %Retrieve the string inside the UIcontrol edit box
    if ~isempty(str2num(num2str(temp))) %This is a nice test of whether there are only numbers or whether there are letters too
        eval(['ProtocolSettings.' paramNames{k} ' = str2num(temp);']);
    else
        eval(['ProtocolSettings.' paramNames{k} ' = temp;']);
    end
end
save(BpodSystem.Path.Settings,'ProtocolSettings');

update = 1;

display('Saved settings and will update in the next round.')
end
 
function changeExpButton(h, ev) %this callback delays the evaluation of the inputs until the next trial is started and sets update to true
global changeExp
changeExp = 1; %Make sure to enter into update mode when the function is called the next time
global BpodSystem
uiresume(BpodSystem.GUIHandles.Figures.FigureAllFigures); %wait for spout control and clear handle afterwards %???
set(h,'String','Starting new experiment'); %Change the button string value
end