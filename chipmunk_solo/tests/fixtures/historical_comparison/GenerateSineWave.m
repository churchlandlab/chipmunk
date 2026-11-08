function signal=GenerateSineWave(rate,frequency,duration)
% Same formula as Mercury's Bpod 1.71 helper; no sound device is opened.
dt=1/double(rate);
t=dt:dt:duration;
signal=sin(2*pi*frequency*t);
end
