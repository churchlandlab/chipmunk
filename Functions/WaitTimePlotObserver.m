function WaitTimePlotObserver(AxesHandle, plotMethod, outcomePlotLimits);
% WaitTimePlotObserver(AxesHandle, plotMethod, outcomePlotLimits);
%
% Function to plot the wait time of the observer in the fixation training
% or the actual observer task. The trial outcome is encoded in the circle
% color while its position indicates the wait time. CAUTION: This
% implementation does not constrain the display of the wait times and therefore
% the y axis range may change dynamically.
%
% -INPUTS: AxesHandle: The handle to the performance plot axes
%         plotMethod: The action to take, 'init' to prepare the plot and
%                     'refresh' to draw the new data.
%         outcomePlotLimits: 1 x 2 vector with the lower and the upper
%                            display limits from the demonstrator outcome
%                            plot.
%
%Adapted from PerformancePlot, LO, 7/14/21
%--------------------------------------------------------------------------

%Input check and assignments
global BpodSystem

%Assign colors
plottingColors(1,:) = [0.35 0.8 0.1]; %Green for successful fixations with reward retrieved, Green open circle for now reward retrieved
plottingColors(2,:) = [0.79 0.2 0.1]; %Red for early withdrawals of the observer
plottingColors(3,:) = [0.5, 0.5, 0.5]; %Gray open circles for non-initiated trials

switch plotMethod
    %%
    case 'init'
        %prepare the display
       axes(AxesHandle);
       set(AxesHandle, 'XLim',[outcomePlotLimits(1) outcomePlotLimits(2)], 'XGrid','off')
       
       %Generate the line objects
       BpodSystem.GUIHandles.ObsSuccessCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(1,:),'MarkerFace',plottingColors(1,:), 'MarkerSize',6);
       BpodSystem.GUIHandles.ObsDidNotHarvestCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(1,:),'MarkerFace',[1 1 1], 'MarkerSize',6);       
       BpodSystem.GUIHandles.ObsEarlyWithdrawalCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(2,:),'MarkerFace',[1 1 1], 'MarkerSize',6);
       BpodSystem.GUIHandles.ObsDidNotInitiateCircle = line([NaN,NaN],[NaN,NaN], 'LineStyle','none','Marker','o','MarkerEdge',plottingColors(3,:),'MarkerFace',[1 1 1], 'MarkerSize',6);
       
       hold(AxesHandle,'on') %Make sure to keep the axes properties
       
       %-------------------------------------------------------------------
  %%     
    case 'refresh'
        
        %Start by settings the x axis limits
        set(AxesHandle, 'XLim',[outcomePlotLimits(1) outcomePlotLimits(2)]);
        
        %Now check the different outcomes and plot accordingly
        successIdx = find(BpodSystem.Data.ObsOutcomeRecord == 1);
        if ~isempty(successIdx)
            Xdata = successIdx; Ydata = BpodSystem.Data.ObsActualWaitTime(Xdata);
            set(BpodSystem.GUIHandles.ObsSuccessCircle, 'xdata',[Xdata Xdata],'ydata',[Ydata Ydata]);
        end
        
        earlyWithdrawalIdx = find(BpodSystem.Data.ObsOutcomeRecord == -1);
        if ~isempty(earlyWithdrawalIdx)
            Xdata = earlyWithdrawalIdx; Ydata = BpodSystem.Data.ObsActualWaitTime(Xdata);
            set(BpodSystem.GUIHandles.ObsEarlyWithdrawalCircle, 'xdata',[Xdata Xdata],'ydata',[Ydata Ydata]);
        end
        
        didNotHarvestIdx = find(BpodSystem.Data.ObsOutcomeRecord == 2);
        if ~isempty(didNotHarvestIdx)
            Xdata = didNotHarvestIdx; Ydata = BpodSystem.Data.ObsActualWaitTime(Xdata);
            set(BpodSystem.GUIHandles.ObsDidNotHarvestCircle, 'xdata',[Xdata Xdata],'ydata',[Ydata Ydata]);
        end
        
        didNotInitiateIdx = find(BpodSystem.Data.ObsOutcomeRecord == -2);
        if ~isempty(didNotInitiateIdx)
            Xdata = didNotInitiateIdx; 
            Ydata = zeros(1,length(Xdata));
            %Since there is no real wait time (NaN) we just set it to zero
            %for display reasons.
            set(BpodSystem.GUIHandles.ObsDidNotInitiateCircle, 'xdata',[Xdata Xdata],'ydata',[Ydata Ydata]);
        end
end

end