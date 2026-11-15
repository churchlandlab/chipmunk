function replayEmulatorSoftCode(code)
global ReplayEmulatorTest
ReplayEmulatorTest.codes(end+1) = code;
SoftCodeHandler_PlaySound(code);
end
