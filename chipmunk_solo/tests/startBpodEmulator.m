function startBpodEmulator()
% Starts Bpod in emulator mode without clicking. Bpod_Gen2 must be on the path.
global BpodSystem
Bpod('EMU');
if ~isequal(BpodSystem.EmulatorMode,1) && isfield(BpodSystem.GUIHandles,'LaunchEmuModeButton')
    b = BpodSystem.GUIHandles.LaunchEmuModeButton;
    feval(get(b,'Callback'),b,[]);
end
assert(BpodSystem.EmulatorMode == 1,'Bpod is not in emulator mode.');
