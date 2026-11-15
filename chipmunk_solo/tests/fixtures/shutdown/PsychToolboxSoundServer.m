function PsychToolboxSoundServer(command)
global ChipmunkShutdownTest
assert(strcmp(command,'Close') && ChipmunkShutdownTest.recording);
ChipmunkShutdownTest.events{end+1}='sound';
if strcmp(ChipmunkShutdownTest.failure,'sound'),error('Test:Sound','Sound close failed');end
end
