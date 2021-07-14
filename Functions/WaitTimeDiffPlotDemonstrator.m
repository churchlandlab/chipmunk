function WaitTimeDiffPlotDemonstrator(AxesHandle, plotMethod, doFitFlag)
%WaitTimeDiffPlotDemonstrator(AxesHandle, plotMethod)
%
%Generates a plot displaying the fraction of right side choices as a
%function of stimulus frequency. It plots visual, auditory and
%multi-sensory modalities separately.
%
%-INPUTS: AxesHandle: The handle to the plot handle
%         plotMethod: The action for the function, 'init' to set up the
%         plot and 'refresh' to add the new data.
%
%The data to be plotted are extracted from BpodSystem.Data.OutcomeRecord,
% -Modality, -StimulusFrequency and -CompletedTrials.
%Note: As of now this function does not feature flexible inputs for
%x limits, or colors.
%
%LO, 1/24/2021
%--------------------------------------------------------------------------

global BpodSystem

plottingColors(1,:) = [0 0 0]; %Target waittime in black
%plottingColors(2,:) = [0.5 0.5 0.5]; %Scattered dots in light gray
plottingColors(3,:) = [0.3, 0.72 0.96]; %Fit line for density in bright blue
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
        set(AxesHandle, 'XLim',[-0.3 1.5],'YLim', [-1.1 0.5], 'Xtick',[0 0.5 1 1.5])
        
        %Generate the line objects
        line(xlim, [0 0], 'Linestyle','-','Color', plottingColors(1,:)); % Plot the zero line
        %BpodSystem.GUIHandles.WatiTimeDiffDots = line([NaN],[NaN], 'LineStyle','none','color',plottingColors(2,:),'Marker','o','MarkerEdge',plottingColors(2,:),'MarkerFace',plottingColors(2,:), 'MarkerSize',2);
        BpodSystem.GUIHandles.WatiTimeDiffDots = scatter([NaN],[NaN],[],[NaN],'filled','SizeData',10);
        BpodSystem.GUIHandles.WaitTimeDiffFitLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(3,:),'LineWidth',1.1);        
        hold(AxesHandle,'on')
        
        %Preallocate memory for displaying the dots on the plot
        BpodSystem.GUIData.WaitTimeDiffPlotDemonstrator.randomShifts = NaN;
        BpodSystem.GUIData.WaitTimeDiffPlotDemonstrator.waitTimeDiff = NaN;
        
        %%     Add the new data
    case 'refresh'
        
        numTrialsDone = length(BpodSystem.Data.ValidTrials); %Do not only rely on completed trials here
        
        %Random x spacing of the individual dots, retain position of them
        BpodSystem.GUIData.WaitTimeDiffPlotDemonstrator.randomShifts(numTrialsDone) = rand*(-0.3); %add a random spacing to the current wait time dot
        Xdata = BpodSystem.GUIData.WaitTimeDiffPlotDemonstrator.randomShifts;
        
        %Calculate the next point
        BpodSystem.GUIData.WaitTimeDiffPlotDemonstrator.waitTimeDiff(numTrialsDone) = BpodSystem.Data.ActualWaitTime(numTrialsDone) - (BpodSystem.Data.SetWaitTime(numTrialsDone) + BpodSystem.Data.PreStimDelay(numTrialsDone) + BpodSystem.Data.PostStimDelay(numTrialsDone));
        Ydata = BpodSystem.GUIData.WaitTimeDiffPlotDemonstrator.waitTimeDiff;
        
        %Set the color properties
        colormap copper %The colormap to use to represent the relative time of each dot
        Cdata = 10/numTrialsDone:10/numTrialsDone:10;
        
        %plot the results
        set(BpodSystem.GUIHandles.WatiTimeDiffDots,'xdata',Xdata,'ydata',Ydata,'cdata',Cdata);
        
        %Fit distribution if enough trials are acquired
        if doFitFlag
            if numTrialsDone >= minNumToFit && sum(~isnan(Ydata)) > 5
                distribObj = fitdist(Ydata',distName); %Needs a column vector of Ydata
                Xdata = (-1.1:0.05:0.5)';
                YdataFit = pdf(distribObj,Xdata); %Generate the fitting line
                set(BpodSystem.GUIHandles.WaitTimeDiffFitLine,'xdata',YdataFit,'ydata',Xdata);
                %Switch them so that the fit is represented vertically
            end
        end
end
end
