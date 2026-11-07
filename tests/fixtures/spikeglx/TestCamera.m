classdef TestCamera < handle
    properties
        reply='ok';
        fail=false;
        failCommand='';
        commands={};
    end
    methods
        function fwrite(s,command)
            if s.fail || strcmp(command,s.failCommand),error('Test:Camera','Camera connection failed');end
            s.commands{end+1}=command;
        end
        function reply=fgetl(s),reply=s.reply;end
    end
end
