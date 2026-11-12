function state=spikeglx_client(command)
global ChipmunkShutdownTest
assert(strcmp(command,'shutdown'));
ChipmunkShutdownTest.events{end+1}='ephys';ChipmunkShutdownTest.recording=false;
state=struct('actionLog',{{'Stopped'}},'lastError','');
end
