function InterTrialIntervalPlotObserver(AxesHandle, plotMethod)
% InterTrialIntervalPlotObserver(AxesHandle, plotMethod)
%
% Generates a bar graph that displays the intervals between trial
% initiations of the observer.
%
% -INPUTS: AxesHandle: The handle to the plot handle
%         plotMethod: The action for the function, 'init' to set up the
%         plot and 'refresh' to add the new data.
%
% The data to be plotted are extracted from BpodSystem.Data.InterTrialInterval,
% 
% Note: As of now this function does not feature flexible inputs for
% x limits, or colors.
%
%LO, 7/14/2021
%--------------------------------------------------------------------------

global BpodSystem

yLimits = [0 30]; %Blantly assume some upper limit for the inter-trial interval

initialXLimits = [1 50]; %The minimum display window
barColor = [0.4 0.4 0.4]; %Pre-specify here
barTransparency = 0.5;

switch plotMethod
    %% Set up the bar graph
    case 'init'
        axes(AxesHandle);
        set(AxesHandle, 'XLim',initialXLimits,'YLim',yLimits)
        
        %Generate the line objects
        BpodSystem.GUIHandles.InterTrialIntervalBar = bar(NaN,'FaceColor',barColor,'FaceAlpha',barTransparency, 'EdgeColor','none');
       
        hold(AxesHandle,'on') %Make sure to keep the axes properties
        
        %--------------------------------------------------------------------------
        %% Include the new data and plot
    case 'refresh'
        %Change the x- and y data of the bar object
        Ydata = BpodSystem.Data.InterTrialInterval;
        Xdata = 1:length(Ydata);
        set(BpodSystem.GUIHandles.InterTrialIntervalBar,'xdata',Xdata,'ydata',Ydata);
        
        %Adapt the display to a growing number of bars added
        if length(Ydata) > initialXLimits(2) - 1
            set(AxesHandle, 'XLim', [0 length(Ydata)+1]);
        end
end
            
        
end
