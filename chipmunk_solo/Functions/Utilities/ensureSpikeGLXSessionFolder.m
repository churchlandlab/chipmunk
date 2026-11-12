function folder = ensureSpikeGLXSessionFolder(dataRoot,subject,session,host)
% Mirror Bpod's subject/session hierarchy on the recording computer.
assert(~isempty(regexp(subject,'^[A-Za-z0-9_-]+$','once')) && ...
    ~isempty(regexp(session,'^\d{8}_\d{6}$','once')), 'Invalid recording subject or session.');
assert(ischar(dataRoot) && ~isempty(dataRoot) && ...
    isempty(regexp(dataRoot,'[\r\n\x00]','once')), 'Recording data root is empty or invalid.');
root=strrep(dataRoot,'\','/');root=regexprep(root,'/+$','');
assert(~any(strcmp(strsplit(root,'/'),'..')), 'Recording data root must not contain parent traversal.');
folder=[root '/' subject '/' session];
if any(strcmpi(host,{'localhost','127.0.0.1','::1'}))
    assert(isfolder(dataRoot),'Recording data root does not exist: %s',dataRoot);
    [ok,message]=mkdir(folder);assert(ok,'%s',message);
else
    assert(~isempty(regexp(root,'^[A-Za-z]:/','once')), 'Remote recording root must be an absolute Windows path.');
    assert(~isempty(regexp(host,'^[A-Za-z0-9][A-Za-z0-9.:-]*$','once')), 'Invalid recording host.');
    quote=@(s) ['''' strrep(s,'''','''''') ''''];
    script=['$ErrorActionPreference=''Stop'';if(-not [IO.Directory]::Exists(' quote(root) ...
        ')){throw ''Recording root does not exist''};[IO.Directory]::CreateDirectory(' quote(folder) ')|Out-Null'];
    encoded=matlab.net.base64encode(unicode2native(script,'UTF-16LE'));
    [status,message]=system(sprintf('ssh -o BatchMode=yes -o ConnectTimeout=5 %s powershell -NoProfile -EncodedCommand %s',host,encoded));
    assert(status==0,'Cannot create recording session folder on %s: %s',host,strtrim(message));
end
end
