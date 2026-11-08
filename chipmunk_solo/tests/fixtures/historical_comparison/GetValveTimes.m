function duration=GetValveTimes(volume,valve)
% Shared deterministic calibration double, not physical valve validation.
duration=double(volume)*.005+valve*.0001;
end
