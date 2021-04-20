function varargout = OutcomePlotDemonstrator(AxesHandle, plotMethod, varargin)
%OutcomePlotDemonstrator(AxesHandle,'init',TrialSidesList)
%OutcomePlotDemonstrator(AxesHandle,'init',TrialSidesList,'ntrials',90)
%plotLimits = OutcomePlotDemonstrator(AxesHandle,'refresh',currentTrial,TrialSidesList,OutcomeRecord);
%
%-INPUTS: AxesHandle: Handle to the axes to plot to.
%         plotMethod: What to do, 'init' start the plotting and 'refresh'
%                     plots the latest results.
%         varargins: TrialSidesList: Numeric vector of 0's (right) or 1's
%                    (left) to indicate reward side (0,1), or 'None' to plot
%                     trial types individually.
%         currentTrial: The trial that is being performed, it is
%                       represented in blue
%         OutcomeRecord:  Vector of trial outcomes
%                               NaN: future trial (gray)
%                                -1: early withdrawal (red circle)
%                                 0: incorrect choice (red dot)
%                                 1: correct choice (green dot)
%                                 2: did not choose (green circle)
%                                -2: no trial initiated (gray circle)
%
% -OUTPUTS: varargout: Only available for refresh mode. The plotting
%                      limits in terms of trials.
%
% Adapted from BControl (SidesPlotSection.m) 
% Kachi O. 2014.Mar.17
% Josh S. 2015.Jan.24 - optimized for speed
% Lukas, 2021.Jan.21 - adapted for chipmunk
%--------------------------------------------------------------------------
%% Global variables and color
global nTrialsToShow %this is for convenience
global BpodSystem

plottingColors = [0.5, 0.5, 0.5]; %Filled gray for trials yet to come, gray circles for non-initiated trials
plottingColors(2,:) = [0.3, 0.72 0.96]; %Bright blue for the current trial
plottingColors(3,:) = [0.35 0.8 0.1]; %Green for correct choices and open green circles for no selection
plottingColors(4,:) = [0.79 0.2 0.1]; %Red for incorrect choices, open red circles for early withdrawals

switch plotMethod
    %%
    case 'init' %initialize pokes plot
        TrialSidesList = varargin{1}; %check for input arguments
        
        nTrialsToShow = 50; %default number of trials to display
        if nargin > 3 %custom number of trials
            nTrialsToShow =varargin{3};
        end
  
        axes(AxesHandle);%plot in specified axes

        Xdata = 1:nTrialsToShow; Ydata = TrialSidesList(Xdata);
        BpodSystem.GUIHandles.FutureTrialCircle = line([Xdata,Xdata],[Ydata,Ydata],'LineStyle','none','Marker','o','MarkerEdge',plottingColors(1,:),'MarkerFace',plottingColors(1,:), 'MarkerSize',6);
        Ydata = TrialSidesList(1); %Plot the first trial in blue already
        BpodSystem.GUIHandles.CurrentTrialCircle = line([1,1],[Ydata Ydata], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(2,:),'MarkerFace',plottingColors(2,:), 'MarkerSize',6);
        %BpodSystem.GUIHandles.CurrentTrialCross = line([0,0],[0,0], 'LineStyle','none','Marker','+','MarkerEdge','k','MarkerFace',[1 1 1], 'MarkerSize',6);
        BpodSystem.GUIHandles.EarlyWithdrawalCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(4,:),'MarkerFace',[1 1 1], 'MarkerSize',6);
        BpodSystem.GUIHandles.PunishedErrorCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(4,:),'MarkerFace',plottingColors(4,:), 'MarkerSize',6);
        BpodSystem.GUIHandles.RewardedCorrectCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(3,:),'MarkerFace',plottingColors(3,:), 'MarkerSize',6);
        %BpodSystem.GUIHandles.UnrewardedCorrectLine = line([0,0],[0,0], 'LineStyle','none','Marker','o','MarkerEdge','g','MarkerFace',[1 1 1], 'MarkerSize',6);
        BpodSystem.GUIHandles.NoResponseCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(3,:),'MarkerFace',[1 1 1], 'MarkerSize',6);
        BpodSystem.GUIHandles.NoTrialStartedCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(1,:),'MarkerFace',[1 1 1], 'MarkerSize',6);
        set(AxesHandle,'TickDir', 'out','YLim', [-1, 2], 'YTick', [0 1],'YTickLabel', {'Left','Right'});
        xlabel(AxesHandle, 'Trial number');
        hold(AxesHandle,'on')
    varargout = {[0 nTrialsToShow]}; %return the shown trials
    %%
    case 'refresh'
        currentTrial = varargin{1};
        TrialSidesList = varargin{2};
        OutcomeRecord = varargin{3};
        
        if currentTrial<1 %Somewhat obsolete check
            currentTrial = 1;
        end
        % recompute xlim
        [mn, mx] = rescaleX(AxesHandle,currentTrial,nTrialsToShow);

        %plot future trials
        FutureTrialsIndx = currentTrial:mx;
        Xdata = FutureTrialsIndx; Ydata = TrialSidesList(Xdata);
        set(BpodSystem.GUIHandles.FutureTrialCircle, 'xdata', [Xdata,Xdata], 'ydata', [Ydata,Ydata]);
        %Plot current trial
        set(BpodSystem.GUIHandles.CurrentTrialCircle, 'xdata', [currentTrial,currentTrial], 'ydata', [TrialSidesList(currentTrial),TrialSidesList(currentTrial)]);
        
        %Plot past trials
        if currentTrial > 1 %Only needed when the current trial is at least the second one
            indxToPlot = mn:currentTrial-1;
            %Plot Error, unpunished
            EarlyWithdrawalTrialsIndx = (OutcomeRecord(indxToPlot) == -1);
            Xdata = indxToPlot(EarlyWithdrawalTrialsIndx); Ydata = TrialSidesList(Xdata);
            set(BpodSystem.GUIHandles.EarlyWithdrawalCircle, 'xdata', [Xdata,Xdata], 'ydata', [Ydata,Ydata]);
            %Plot Error, punished
            InCorrectTrialsIndx = (OutcomeRecord(indxToPlot) == 0);
            Xdata = indxToPlot(InCorrectTrialsIndx); Ydata = TrialSidesList(Xdata);
            set(BpodSystem.GUIHandles.PunishedErrorCircle, 'xdata', [Xdata,Xdata], 'ydata', [Ydata,Ydata]);
            %Plot Correct, rewarded
            CorrectTrialsIndx = (OutcomeRecord(indxToPlot) == 1);
            Xdata = indxToPlot(CorrectTrialsIndx); Ydata = TrialSidesList(Xdata);
            set(BpodSystem.GUIHandles.RewardedCorrectCircle, 'xdata', [Xdata,Xdata], 'ydata', [Ydata,Ydata]);
            %Plot Correct, unrewarded
%             UnrewardedTrialsIndx = (OutcomeRecord(indxToPlot) == 2);
%             Xdata = indxToPlot(UnrewardedTrialsIndx); Ydata = SideList(Xdata);
%             set(BpodSystem.GUIHandles.UnrewardedCorrectLine, 'xdata', [Xdata,Xdata], 'ydata', [Ydata,Ydata]);
            %Plot DidNotChoose
            DidNotChooseTrialsIndx = (OutcomeRecord(indxToPlot) == 2);
            Xdata = indxToPlot(DidNotChooseTrialsIndx); Ydata = TrialSidesList(Xdata);
            set(BpodSystem.GUIHandles.NoResponseCircle, 'xdata', [Xdata,Xdata], 'ydata', [Ydata,Ydata]);
            %Plot no trial initiation
            noInitiationIndx = (OutcomeRecord(indxToPlot) == -2);
            Xdata = indxToPlot(noInitiationIndx); Ydata = TrialSidesList(Xdata);
            set(BpodSystem.GUIHandles.NoTrialStartedCircle, 'xdata', [Xdata,Xdata], 'ydata', [Ydata,Ydata]);
        end
        varargout = {[mn, mx]}; %Return the new plot limits if in the refresh mode.
end

end

function [mn,mx] = rescaleX(AxesHandle,currentTrial,nTrialsToShow)
FractionWindowStickpoint = .75; % After this fraction of visible trials, the trial position in the window "sticks" and the window begins to slide through trials.
mn = max(round(currentTrial - FractionWindowStickpoint*nTrialsToShow),1); %Find whether the first term is larger than 1
mx = mn + nTrialsToShow - 1;
set(AxesHandle,'XLim',[mn-1 mx+1]);
end


