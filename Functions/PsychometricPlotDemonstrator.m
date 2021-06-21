function PsychometricPlotDemonstrator(AxesHandle, plotMethod)
%PsychometricPlotDemonstrator(AxesHandle, plotMethod)
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
% -Modality, -StimulusRate and -ValidTrials.
%Note: As of now this function does not feature flexible inputs for
%x limits, or colors.
%
%LO, 1/24/2021
%--------------------------------------------------------------------------

global BpodSystem

freqLimits = [0 24]; %The Stimulus frequency range to show on the plot
displayXTicks = [4 8 12 16 20]; %Pre set the x-ticks to show

plottingColors = [0.02 0.26 0.54]; %plot visual stimuli on dark blue
plottingColors(2,:) = [0.02 0.56 0.4]; %plot auditory stimuli in dark green
plottingColors(3,:) = [0.3 0.3 0.3]; %plot multi-sensory stimuli in dark gray

switch plotMethod
    %% Set up the psychometric plot
    case 'init'
        axes(AxesHandle);
        set(AxesHandle, 'XLim',[freqLimits(1) freqLimits(2)],'YLim', [0 1])
        xticks(displayXTicks)
        
        %Generate the line objects
        BpodSystem.GUIHandles.VisualPsychometricLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(1,:),'Marker','o','MarkerEdge',plottingColors(1,:),'MarkerFace',plottingColors(1,:), 'MarkerSize',4);
        BpodSystem.GUIHandles.AuditoryPsychometricLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(2,:),'Marker','o','MarkerEdge',plottingColors(2,:),'MarkerFace',plottingColors(2,:),'MarkerSize',4);
        BpodSystem.GUIHandles.MultiSensoryPsychometricLine = line([NaN],[NaN], 'LineStyle','-','color',plottingColors(3,:),'Marker','o','MarkerEdge',plottingColors(3,:),'MarkerFace',plottingColors(3,:),'MarkerSize',4);
        
        %Work on the legend       
        %Generate a set of empty lines to label the legend
        dummyL1 = line(nan, nan, 'Linestyle', 'none', 'Marker', 'none', 'Color', 'none');  %Generate a dummy line
        dummyL2 = line(nan, nan, 'Linestyle', 'none', 'Marker', 'none', 'Color', 'none');  %Generate a dummy line
        dummyL3 = line(nan, nan, 'Linestyle', 'none', 'Marker', 'none', 'Color', 'none');  %Generate a dummy line
        
        %Just display all the legends for now
            [BpodSystem.GUIHandles.PsychometricPlotLegend, lObj] = legend([dummyL1, dummyL2, dummyL3], {'Visual','Auditory','Multi'},'box','off'); %Legend for the dummy with no line or markers
            lObj(1).Color = plottingColors(1,:);
            lObj(2).Color = plottingColors(2,:);
            lObj(3).Color = plottingColors(3,:);
        
        %Lift legend a bit and fit to left side or right depending on the high rate side
       BpodSystem.GUIHandles.PsychometricPlotLegend.Position(2) = 0.44; %Lift it up a bit
        if strcmpi(BpodSystem.ProtocolSettings.highRateSide,'R')
            BpodSystem.GUIHandles.PsychometricPlotLegend.Position(1) = 0.035;
        else
            BpodSystem.GUIHandles.PsychometricPlotLegend.Position(1) = 0.17;
        end
 
        hold(AxesHandle,'on') %Make sure to keep the axes properties
        
        %--------------------------------------------------------------------------
        %% Include the new data and plot
    case 'refresh'
        %Check back whether the side record is still correct
         if strcmpi(BpodSystem.ProtocolSettings.highRateSide,'R') &&  BpodSystem.GUIHandles.PsychometricPlotLegend.Position(1) ~= 0.016
            BpodSystem.GUIHandles.PsychometricPlotLegend.Position(1) = 0.035;
         elseif strcmpi(BpodSystem.ProtocolSettings.highRateSide,'L') &&  BpodSystem.GUIHandles.PsychometricPlotLegend.Position(1) ~= 0.126
            BpodSystem.GUIHandles.PsychometricPlotLegend.Position(1) = 0.17;
         end
        
        numTrialsDone = length(BpodSystem.Data.ValidTrials); %Get the number of completed trial to decide on the plotting
        %Go through the different modalities. First, get the completed
        %trials of the respective modality.
        %Visual
        completedVisualTrials = BpodSystem.Data.ResponseSide(BpodSystem.Data.ValidTrials==1 & BpodSystem.Data.Modality==1); %check all the trials so far
        visualFrequencies = BpodSystem.Data.StimulusRate(BpodSystem.Data.ValidTrials==1 & BpodSystem.Data.Modality==1);
        Xdata = unique(visualFrequencies); %find the different frequencies that used so far
        if ~isempty(Xdata) %check whether there are actually data
            for k = 1:length(Xdata)
                Ydata(k) = mean(completedVisualTrials(visualFrequencies == Xdata(k))); %Get the average number of right choices for the respective frequency
            end
            set(BpodSystem.GUIHandles.VisualPsychometricLine,'xdata',Xdata,'ydata',Ydata);
        end
        
        %Auditory
        completedAuditoryTrials = BpodSystem.Data.ResponseSide(BpodSystem.Data.ValidTrials==1 & BpodSystem.Data.Modality==2);
        auditoryFrequencies = BpodSystem.Data.StimulusRate(BpodSystem.Data.ValidTrials==1 & BpodSystem.Data.Modality==2);
        Xdata = unique(auditoryFrequencies); %find the different frequencies that used so far
        if ~isempty(Xdata)
            for k = 1:length(Xdata)
                Ydata(k) = mean(completedAuditoryTrials(auditoryFrequencies == Xdata(k))); %Get the average number of right choices for the respective frequency
            end
            set(BpodSystem.GUIHandles.AuditoryPsychometricLine,'xdata',Xdata,'ydata',Ydata);
        end
        
        %Multi-sensory
        completedMultiSensoryTrials = BpodSystem.Data.ResponseSide(BpodSystem.Data.ValidTrials==1 & BpodSystem.Data.Modality==3);
        multiSensoryFrequencies = BpodSystem.Data.StimulusRate(BpodSystem.Data.ValidTrials==1 & BpodSystem.Data.Modality==3);
        Xdata = unique(multiSensoryFrequencies); %find the different frequencies that used so far
        if ~isempty(Xdata)
            for k = 1:length(Xdata)
                Ydata(k) = mean(completedMultiSensoryTrials(multiSensoryFrequencies == Xdata(k))); %Get the average number of right choices for the respective frequency
            end
            set(BpodSystem.GUIHandles.MultiSensoryPsychometricLine,'xdata',Xdata,'ydata',Ydata);
        end
        
end
end
