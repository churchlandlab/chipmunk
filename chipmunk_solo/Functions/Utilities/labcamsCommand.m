function reply = labcamsCommand(socket, command, waitForReply)
% Labcams replies are complete datagrams without a line terminator.
if nargin < 3, waitForReply = true; end
destination = socket.UserData;
flush(socket,'input');
write(socket,uint8(command),'uint8',destination.host,destination.port);
reply = '';
if ~waitForReply, return; end
action = strtok(command,'=');
switch action
    case 'ping', action = 'pong';
    case 'softtrigger', action = 'trigger';
    case 'manualsave', action = 'save';
    case 'quit', action = 'bye';
end
started = tic;
while toc(started) < socket.Timeout
    if socket.NumDatagramsAvailable > 0
        packet = read(socket,1,'uint8');
        value = strtrim(char(packet.Data));
        if strcmp(value,['ok=' action]) || startsWith(lower(value),'error')
            reply = value;
            return
        end
    else
        pause(.01);
    end
end
end
