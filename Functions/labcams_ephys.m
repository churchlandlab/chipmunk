function [ok,message] = labcams_ephys(cmd)
% A configured camera must acknowledge commands before task Start succeeds.
    global BpodSystem
    ok=true;message='';
    hasSettings=(isstruct(BpodSystem) && isfield(BpodSystem,'ProtocolSettings')) || ...
        (isobject(BpodSystem) && isprop(BpodSystem,'ProtocolSettings'));
    configured=hasSettings && isfield(BpodSystem.ProtocolSettings,'labcamsAddress') && ...
        ~isempty(strtrim(BpodSystem.ProtocolSettings.labcamsAddress));
    hasPlugins=(isstruct(BpodSystem) && isfield(BpodSystem,'PluginObjects')) || ...
        (isobject(BpodSystem) && isprop(BpodSystem,'PluginObjects'));
    if ~hasPlugins || ~isfield(BpodSystem.PluginObjects,'labcams') || isempty(BpodSystem.PluginObjects.labcams)
        if configured,ok=false;message='Configured labcams connection is unavailable.';end
        return
    end
    u=BpodSystem.PluginObjects.labcams;
    try
        switch cmd
            case 'start',commands={'softtrigger=0','manualsave=1','softtrigger=1'};
            case 'stop',commands={'softtrigger=0','manualsave=0'};
            otherwise,error('labcams_ephys: unknown command %s',cmd);
        end
        for k=1:numel(commands)
            fwrite(u,commands{k});
            reply=fgetl(u);
            assert(ischar(reply) && ~isempty(strtrim(reply)) && ...
                ~startsWith(strtrim(lower(reply)),'error'), ...
                'No successful labcams acknowledgement for %s.',commands{k});
            if strcmp(cmd,'start') && k==2,pause(.5);end
        end
    catch ME
        ok=false;message=['Camera ' cmd ' failed: ' ME.message];
        if strcmp(cmd,'start')
            [stopped,stopMessage]=labcams_ephys('stop');
            if ~stopped,message=[message ' Camera cleanup also failed: ' stopMessage];end
        end
    end
end
