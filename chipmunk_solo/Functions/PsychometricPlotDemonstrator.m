function PsychometricPlotDemonstrator(AxesHandle, plotMethod)
% Plot the fraction of right choices at each stimulus rate, by modality.
% Only valid trials contribute. Auditory trials use StimulusRate column 2;
% visual and multisensory trials use column 1.
global BpodSystem

if strcmpi(BpodSystem.ProtocolSettings.highRateSide, 'R')
    legendLocation = 'northwest';
else
    legendLocation = 'northeast';
end

switch plotMethod
    case 'init'
        plottingColors = [0.02 0.26 0.54; 0.02 0.56 0.4; 0.3 0.3 0.3];
        set(AxesHandle, 'XLim', [0 24], 'YLim', [0 1], 'XTick', [4 8 12 16 20]);
        lines = gobjects(1, 3);
        for modality = 1:3
            lines(modality) = line(AxesHandle, nan, nan, ...
                'Color', plottingColors(modality,:), 'LineStyle', '-', ...
                'Marker', 'o', 'MarkerFaceColor', plottingColors(modality,:), ...
                'MarkerSize', 4);
        end
        BpodSystem.GUIHandles.VisualPsychometricLine = lines(1);
        BpodSystem.GUIHandles.AuditoryPsychometricLine = lines(2);
        BpodSystem.GUIHandles.MultiSensoryPsychometricLine = lines(3);
        % A single output avoids MATLAB's legacy legend layout on tabs.
        BpodSystem.GUIHandles.PsychometricPlotLegend = legend(AxesHandle, lines, ...
            {'Visual', 'Auditory', 'Multi'}, 'Box', 'off', ...
            'Location', legendLocation, 'AutoUpdate', 'off');
        hold(AxesHandle, 'on');

    case 'refresh'
        BpodSystem.GUIHandles.PsychometricPlotLegend.Location = legendLocation;
        lines = [BpodSystem.GUIHandles.VisualPsychometricLine, ...
            BpodSystem.GUIHandles.AuditoryPsychometricLine, ...
            BpodSystem.GUIHandles.MultiSensoryPsychometricLine];
        for modality = 1:3
            valid = BpodSystem.Data.ValidTrials == 1 & BpodSystem.Data.Modality == modality;
            responses = BpodSystem.Data.ResponseSide(valid);
            rateColumn = 1 + (modality == 2);
            frequencies = BpodSystem.Data.StimulusRate(valid, rateColumn);
            Xdata = unique(frequencies);
            Ydata = zeros(size(Xdata));
            for k = 1:numel(Xdata)
                Ydata(k) = mean(responses(frequencies == Xdata(k)));
            end
            set(lines(modality), 'XData', Xdata, 'YData', Ydata);
        end
end
end
