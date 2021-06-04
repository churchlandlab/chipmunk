function StimulusPlotDemonstrator(AxesHandleVisual, AxesHandleAuditory, plotMethod, varargin)
%StimulusPlotDemonstrator(AxesHandleVisual, AxesHandleAuditory, plotMethod, varargin)
%
%Plots the visual and auditory stimulus signals.
%
%-INPUTS: AxesHandleVisual: The handle to the axes that will display the
%                           visual stimulus.
%         AxesHandleAuditory: Same for the auditory siganl.
%         plotMethod: The action to perform, either 'init' to set the plots
%                     up or 'refresh' to plot upcoming stimuli.
%         varargin: Depends on the plotMethod: If it is 'init' the argument
%                   is the sampling rate of the sound card (1) and the
%                   duration of the stim train (2).
%                   If the plotMethod is 'refresh' it holds the actual
%                   signal as a 2 x sampling rate vector, where the first
%                   row is the visual the second row the auditory signal.
%
% LO, 4/19/2021
%--------------------------------------------------------------------------
global BpodSystem

plottingColors = [0.02 0.26 0.54]; %plot visual stimuli on dark blue
plottingColors(2,:) = [0.02 0.56 0.4]; %plot auditory stimuli in dark green

switch plotMethod
    %%
    case 'init'
        samples = varargin{1}; %Retrieve the used sampling rate
        stimTrainDuration = varargin{2}; %The duration of the signal
        
        %Intialize the visual stimulus panel first
        axes(AxesHandleVisual)
        set(AxesHandleVisual, 'XLim',[0 1]) %What is the ylimit?
        BpodSystem.GUIHandles.StimulusPlotVisualLine = line(NaN, NaN, 'LineStyle','-','color',plottingColors(1,:));
        %hold(AxesHandleVisual,'on')
        
         %Now the auditory stimulus plot
        axes(AxesHandleAuditory)
        set(AxesHandleAuditory, 'XLim',[0 1]) %What is the ylimit?
        BpodSystem.GUIHandles.StimulusPlotAuditoryLine = line(NaN, NaN, 'LineStyle','-','color',plottingColors(2,:));
        %hold(AxesHandleAuditory,'on')
        
        %Store the Xdata
        BpodSystem.GUIData.StimulusPlotDemonstrator.Xdata = 1/samples:1/samples:stimTrainDuration;
        
         %%
    case 'refresh'
        stimulusSignals = varargin{1}; %get the signals
        
        %First visual
        axes(AxesHandleVisual) 
        set(BpodSystem.GUIHandles.StimulusPlotVisualLine,'xdata', BpodSystem.GUIData.StimulusPlotDemonstrator.Xdata,...
            'ydata', stimulusSignals(1,:)); %Visual waveform is in the first row
        
        %Second auditory
        axes(AxesHandleAuditory) 
        set(BpodSystem.GUIHandles.StimulusPlotAuditoryLine,'xdata', BpodSystem.GUIData.StimulusPlotDemonstrator.Xdata,...
            'ydata', stimulusSignals(2,:)); %Auditroy waveform in the second row
        
end

end