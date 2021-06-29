function PerformancePlotDemonstrator(AxesHandle, plotMethod, outcomePlotLimits, displayParam)
%PerformancePlotDemonstrator(AxesHandle, plotMethod, outcomePlotLimits, displayParam)
%
%Function to plot the demonstrator performance on left side trials, on 
%right side trials and on both as a function of trial number. This function
%uses processed trial data that are not passed as arguments but that are
%stored in BpodSystem.Data
%
%-INPUTS: AxesHandle: The handle to the performance plot axes
%         plotMethod: The action to take, 'init' to prepare the plot and
%                     'refresh' to draw the new data.
%         outcomePlotLimits: 1 x 2 vector with the lower and the upper
%                            display limits from the demonstrator outcome
%                            plot.
%         displayParam (optional): A struct containing the following fields:
%                       -performanceWindow: How many trials should be
%                       considered for the performance calculation, default
%                       = 24.
%                       -displayInterval: The interval at which new lines
%                       and dots will be displayed, default = 4.
%                       -initialDisplayWindow: The initial upper x-axis
%                       (trial number) limit, defualt = 200.
%                       -minValidTrials: Minimum number of valid trials to
%                       display the performance, default = 3.
%
%Adapted from PerformancePlot, LO, 1/22/21
%--------------------------------------------------------------------------

%Input check and assignments
global BpodSystem

if ~exist('displayParam') || isempty(displayParam) %input check
    performanceWindow = 24; %over these many trials the performance will be calculated
    displayInterval = 4; %At this frequency the performance will be plotted.
    %The overlap between the points will be displayInterval/performanceWindow
    initialDisplayWindow = 200; %Start populating the plot until 200 are reached and squeeze afterwards
    minValidTrials = 3; %The minimum of completed trials to display the performance
else
    performanceWindow = displayParam.performanceWindow;
    displayInterval = displayParam.displayInterval;
    initialDisplayWindow = displayParam.initialDisplayWindow;
    minValidTrials = displayParam.minValidTrials;
end

%Assign colors
plottingColors = [0.8 0.46 0.1]; %Performance on left trials in orange
plottingColors(2,:) = [0.46 0.1 0.8]; %Performance on right trials in purple
plottingColors(3,:) = [0.3 0.3 0.3]; %Overall performance in dark gray
plottingColors(4, :) = [0.3, 0.72 0.96]; %Lines to indicate outcome plot limits in bright blue

switch plotMethod
    %%
    case 'init'
        %prepare the display
       axes(AxesHandle);
       set(AxesHandle, 'XLim',[0 initialDisplayWindow],'YLim', [-0.1 1.1], 'XGrid','off')
       
       %Draw the verical lines indicating the outcome plot limits
       BpodSystem.GUIHandles.OutcomeLowerLimitLine = line([outcomePlotLimits(1) outcomePlotLimits(1)], ylim, 'LineStyle','-','color', plottingColors(4,:));
       BpodSystem.GUIHandles.OutcomeUpperLimitLine = line([outcomePlotLimits(2) outcomePlotLimits(2)], ylim, 'LineStyle','-','color', plottingColors(4,:));
       
       %Generate the line objects
       BpodSystem.GUIHandles.LeftPerformanceLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(1,:),'Marker','o','MarkerEdge',plottingColors(1,:),'MarkerFace',plottingColors(1,:), 'MarkerSize',3);
       BpodSystem.GUIHandles.RightPerformanceLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(2,:),'Marker','o','MarkerEdge',plottingColors(2,:),'MarkerFace',plottingColors(2,:), 'MarkerSize',3);
       BpodSystem.GUIHandles.OverallPerformanceLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(3,:),'Marker','o','MarkerEdge',plottingColors(3,:),'MarkerFace',plottingColors(3,:), 'MarkerSize',4);
       
       %Labels
       legend([BpodSystem.GUIHandles.LeftPerformanceLine, BpodSystem.GUIHandles.RightPerformanceLine,...
           BpodSystem.GUIHandles.OverallPerformanceLine], {'Left trials', 'Right trials', 'Overall'},...
           'Location','southeast','Orientation','horizontal','box','off'); 
       hold(AxesHandle,'on') %Make sure to keep the axes properties
       
       %Preallocate variables for the performance in GUIData
       BpodSystem.GUIData.PerformancePlotDemonstrator.leftLineData = [];
       BpodSystem.GUIData.PerformancePlotDemonstrator.rightLineData = [];
       BpodSystem.GUIData.PerformancePlotDemonstrator.overallLineData = [];
       BpodSystem.GUIData.PerformancePlotDemonstrator.xaxis = [];
       %-------------------------------------------------------------------
  %%     
    case 'refresh'
        
        %Make sure to adapt the window size if more than the initial
        %trials have been done already and start squeezing
        if outcomePlotLimits(2) > initialDisplayWindow - displayInterval
            set(AxesHandle, 'XLim',[0 outcomePlotLimits(2)+displayInterval])
        end
        %Move the outcome plot limit lines on every trial
         set(BpodSystem.GUIHandles.OutcomeLowerLimitLine, 'xdata', [outcomePlotLimits(1) outcomePlotLimits(1)])
         set(BpodSystem.GUIHandles.OutcomeUpperLimitLine, 'xdata', [outcomePlotLimits(2) outcomePlotLimits(2)])
                  
numTrialsDone = length(BpodSystem.Data.OutcomeRecord); %Get the number of completed trial to decide on the plotting

        if numTrialsDone >= performanceWindow %only start plotting whe enough data has been acquired
            if mod(numTrialsDone,displayInterval) == 0 %only plot at the given interval
                %Check for the number of trials that were actually
                %completed and show no performance if there are too few
                lowerWin = (numTrialsDone-performanceWindow)+1; %lower bound of trials to consider
               if sum(BpodSystem.Data.ValidTrials(lowerWin:numTrialsDone)) >= minValidTrials
                   setOfOutcomes = BpodSystem.Data.OutcomeRecord(lowerWin:numTrialsDone);
                   setOfOutcomes(setOfOutcomes > 1) = NaN; %Reomove info of non-completed trials
                   setOfOutcomes(setOfOutcomes < 0) = NaN;
                   BpodSystem.GUIData.PerformancePlotDemonstrator.overallLineData(end+1) = nanmean(setOfOutcomes); %overall performance
                   BpodSystem.GUIData.PerformancePlotDemonstrator.leftLineData(end+1) = nanmean(setOfOutcomes(BpodSystem.Data.CorrectSide(lowerWin:numTrialsDone)==0));
                   BpodSystem.GUIData.PerformancePlotDemonstrator.rightLineData(end+1) = nanmean(setOfOutcomes(BpodSystem.Data.CorrectSide(lowerWin:numTrialsDone)==1));
                   BpodSystem.GUIData.PerformancePlotDemonstrator.xaxis(end+1) = numTrialsDone - displayInterval; %Append onto the Xaxis
                   
                   %Change the line properties
                   Xdata = BpodSystem.GUIData.PerformancePlotDemonstrator.xaxis;
                   %Overall performance
                   Ydata = BpodSystem.GUIData.PerformancePlotDemonstrator.overallLineData;
                   set(BpodSystem.GUIHandles.OverallPerformanceLine,'xdata',Xdata,'ydata',Ydata);
                   %Left side trials
                   Ydata = BpodSystem.GUIData.PerformancePlotDemonstrator.leftLineData;
                   set(BpodSystem.GUIHandles.LeftPerformanceLine,'xdata',Xdata,'ydata',Ydata);
                   %Right side trials
                   Ydata = BpodSystem.GUIData.PerformancePlotDemonstrator.rightLineData;
                   set(BpodSystem.GUIHandles.RightPerformanceLine,'xdata',Xdata,'ydata',Ydata);
        
               else %the case that there are not enough completed trials to make a reasonable statement
                   BpodSystem.GUIData.PerformancePlotDemonstrator.overallLineData(end+1) = NaN;
                   BpodSystem.GUIData.PerformancePlotDemonstrator.leftLineData(end+1) = NaN;
                   BpodSystem.GUIData.PerformancePlotDemonstrator.rightLineData(end+1) = NaN;
                   BpodSystem.GUIData.PerformancePlotDemonstrator.xaxis(end+1) = numTrialsDone - displayInterval; %Append onto the Xaxis
                   
                    %Change the line properties
                   Xdata = BpodSystem.GUIData.PerformancePlotDemonstrator.xaxis;
                   %Overall performance
                   Ydata = BpodSystem.GUIData.PerformancePlotDemonstrator.overallLineData;
                   set(BpodSystem.GUIHandles.OverallPerformanceLine,'xdata',Xdata,'ydata',Ydata);
                   %Left side trials
                   Ydata = BpodSystem.GUIData.PerformancePlotDemonstrator.leftLineData;
                   set(BpodSystem.GUIHandles.LeftPerformanceLine,'xdata',Xdata,'ydata',Ydata);
                   %Right side trials
                   Ydata = BpodSystem.GUIData.PerformancePlotDemonstrator.rightLineData;
                   set(BpodSystem.GUIHandles.RightPerformanceLine,'xdata',Xdata,'ydata',Ydata);
               end
            end
        end
end

end