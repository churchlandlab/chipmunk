function InitiationTimePlotObserver(AxesHandle, plotMethod, doFitFlag)
%InitiationTimePlotObserver(AxesHandle, plotMethod)
%
%Generate a summary of the time it requires the observer to start fixation
%after hearing the cue indicating that the demonstrator is fixating.
%
%-INPUTS: AxesHandle: The handle to the plot handle
%         plotMethod: The action for the function, 'init' to set up the
%         plot and 'refresh' to add the new data.
%
%The data to be plotted are extracted from BpodSystem.Data.ObsInitiationTime.
%
%LO, 1/11/2022
%--------------------------------------------------------------------------

global BpodSystem

plottingColors(1,:) = [0.25 0.25 0.25]; %Scatter color
plottingColors(2,:) = [0.92, 0.64 0.07]; %Fit line for density in orange
colormap copper

if exist('doFitFlag')
    if ~isempty(doFitFlag) && doFitFlag
        minNumToFit = 20; %Minimum number of trials to fit the distribution
        distName = 'Kernel'; %Distribution type to fit
    else
        doFitFlag = false;
    end
else
    doFitFlag = false;
end

switch plotMethod
    %% Set up the wait time plot
    case 'init'
        axes(AxesHandle);        
        %Generate the line objects
        BpodSystem.GUIHandles.InitiationTimeDots = scatter([NaN],[NaN],[],[NaN],'filled','MarkerFaceColor',plottingColors(1,:),'SizeData',6);
        BpodSystem.GUIHandles.InitiationTimeFitLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(2,:),'LineWidth',1);        
        
        hold(AxesHandle,'on')
        
        %Preallocate memory for displaying the dots on the plot
        %BpodSystem.GUIData.InitiationTimePlotObserver.randomShifts = NaN;
        
        %%     Add the new data
    case 'refresh'
        
        numTrialsDone = length(BpodSystem.Data.ObsInitiationTime); %Do not only rely on completed trials here
        
        %Random x spacing of the individual dots, adjust to the size of the
        %fit.
        if ~isnan(BpodSystem.GUIHandles.InitiationTimeFitLine.XData)
        Xdata = max(BpodSystem.GUIHandles.InitiationTimeFitLine.XData)*rand(1,numTrialsDone);
        else
        Xdata = rand(1,numTrialsDone);
        end
        
        Ydata = BpodSystem.Data.ObsInitiationTime;
        
        %plot the results
        set(BpodSystem.GUIHandles.InitiationTimeDots,'xdata',Xdata,'ydata',Ydata);
        
        %Fit distribution if enough trials are acquired
        if doFitFlag
            if numTrialsDone >= minNumToFit && sum(~isnan(Ydata)) > 5
                distribObj = fitdist(Ydata',distName); %Needs a column vector of Ydata
                Xdata = (0:0.05:BpodSystem.ProtocolSettings.obsInitiationWindow)';
                YdataFit = pdf(distribObj,Xdata); %Generate the fitting line
                set(BpodSystem.GUIHandles.InitiationTimeFitLine,'xdata',YdataFit,'ydata',Xdata);
                %Switch them so that the fit is represented vertically
            end
        end
end
end
