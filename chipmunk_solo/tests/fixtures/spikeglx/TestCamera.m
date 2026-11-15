classdef TestCamera < handle
    properties
        reply='ok';
        fail=false;
        failCommand='';
        commands={};
    end
    methods
        function reply=labcamsCommand(s,command,varargin)
            if s.fail || strcmp(command,s.failCommand),error('Test:Camera','Camera connection failed');end
            s.commands{end+1}=command;
            reply=s.reply;
        end
    end
end
