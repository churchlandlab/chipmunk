function PsychToolboxSoundServer(command,varargin)
global ReplayTest
switch lower(command)
    case 'load'
        ReplayTest.loads{end+1} = varargin{2};
    case 'stopall'
        ReplayTest.stops = ReplayTest.stops+1;
end
end
