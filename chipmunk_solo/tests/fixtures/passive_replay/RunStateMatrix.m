function events = RunStateMatrix()
global BpodSystem ReplayTest
ReplayTest.runs = ReplayTest.runs+1;
switch ReplayTest.mode
    case 'complete'
        events = struct('States',1:5);
    case 'abort'
        BpodSystem.Status.BeingUsed = 0;
        events = struct('States',1:3);
    case 'error'
        error('ReplayTest:Injected','Controlled run failure');
    case 'empty'
        events = struct();
end
end
