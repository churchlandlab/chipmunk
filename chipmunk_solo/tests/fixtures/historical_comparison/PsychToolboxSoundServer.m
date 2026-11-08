function PsychToolboxSoundServer(command,slot,signal)
global HistoricalCues
assert(strcmpi(command,'Load'));
HistoricalCues{slot}=signal;
end
