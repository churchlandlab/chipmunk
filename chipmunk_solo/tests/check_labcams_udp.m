function check_labcams_udp
root=fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(root,'Functions')));
server=udpport('datagram','IPV4','LocalHost','127.0.0.1');
client=udpport('datagram','IPV4','LocalHost','127.0.0.1','Timeout',2);
cleanup=onCleanup(@() closeSockets(server,client));
client.UserData=struct('host','127.0.0.1','port',server.LocalPort);
mode='normal';commands={};
configureCallback(server,'datagram',1,@respond);
lastwarn('');
% Cold MATLAB callback initialization can exceed the short timeout below.
assert(strcmp(labcamsCommand(client,'ping'),'ok=pong'));
client.Timeout=.2;
assert(strcmp(labcamsCommand(client,'softtrigger=1'),'ok=trigger'));
assert(strcmp(labcamsCommand(client,'manualsave=1'),'ok=save'));
% A delayed log acknowledgement must not confirm a later recording command.
mode='stale';assert(strcmp(labcamsCommand(client,'manualsave=0'),'ok=save'));
mode='error';assert(strcmp(labcamsCommand(client,'manualsave=1'),'error=cannot_save'));
mode='silent';started=tic;assert(isempty(labcamsCommand(client,'ping')));
assert(toc(started)>=.2 && toc(started)<2);
started=tic;labcamsCommand(client,'log=test',false);assert(toc(started)<.2);
pause(.05);assert(ismember('log=test',commands));
[message,~]=lastwarn;assert(isempty(message),message);
fprintf('PASS: UDP datagram replies, stale acknowledgements, errors, quiet timeout and asynchronous logs\n');

    function respond(socket,~)
        packets=read(socket,socket.NumDatagramsAvailable,'uint8');
        for i=1:numel(packets)
            p=packets(i);command=char(p.Data);commands{end+1}=command;
            if strcmp(mode,'silent'),continue;end
            if strcmp(mode,'error'),reply='error=cannot_save';
            else
                action=strtok(command,'=');
                switch action
                    case 'ping',action='pong';
                    case 'softtrigger',action='trigger';
                    case 'manualsave',action='save';
                end
                reply=['ok=' action];
            end
            if strcmp(mode,'stale'),write(socket,uint8('ok=log'),'uint8',p.SenderAddress,p.SenderPort);end
            write(socket,uint8(reply),'uint8',p.SenderAddress,p.SenderPort);
        end
    end
end

function closeSockets(server,client)
configureCallback(server,'off');delete(server);delete(client);
end
