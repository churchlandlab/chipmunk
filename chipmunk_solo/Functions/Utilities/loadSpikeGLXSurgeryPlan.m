function profile = loadSpikeGLXSurgeryPlan(folder,subject,host)
% Read shared VVASP records and reject atlas labels derived from stale sources.
assert(~isempty(regexp(subject,'^[A-Za-z0-9_-]+$','once')),'Invalid surgery-plan subject.');
profile=[];raw=[];paired=false;
if ~isempty(regexp(folder,'^[A-Za-z]:[\\/]','once')) && ...
        ~any(strcmpi(host,{'localhost','127.0.0.1','::1'}))
    assert(~isempty(regexp(host,'^[A-Za-z0-9][A-Za-z0-9.:-]*$','once')),'Invalid recording host.');
    quote=@(s) ['''' strrep(s,'''','''''') ''''];
    script=['$ProgressPreference=''SilentlyContinue'';$ErrorActionPreference=''Stop'';$root=' quote(folder) ';' ...
        'if(-not [IO.Directory]::Exists($root)){throw ''VVASP folder does not exist''};' ...
        '$file=Join-Path $root ' quote(['anatomy/' subject '.json']) ';' ...
        'if(-not [IO.File]::Exists($file)){Write-Output ''null'';exit};' ...
        '$profile=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json;' ...
        '$name=$profile.provenance.sourceFile;' ...
        'if($name -notmatch ''^[A-Za-z0-9_-]+\.json$''){throw ''Invalid VVASP source filename''};' ...
        '$source=Join-Path (Join-Path $root ''experiments'') $name;' ...
        '@{profile=$profile;sourceBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($source))}' ...
        '|ConvertTo-Json -Depth 20 -Compress'];
    encoded=matlab.net.base64encode(unicode2native(script,'UTF-16LE'));
    [status,message]=system(sprintf('ssh -o BatchMode=yes -o ConnectTimeout=5 %s powershell -NoProfile -EncodedCommand %s',host,encoded));
    assert(status==0,'Cannot read VVASP records on %s: %s',host,strtrim(message));
    data=jsondecode(message);if isempty(data),return;end
    profile=data.profile;raw=matlab.net.base64decode(data.sourceBase64);paired=true;
elseif isfolder(fullfile(folder,'anatomy'))
    file=fullfile(folder,'anatomy',[subject '.json']);if ~isfile(file),return;end
    profile=jsondecode(fileread(file));
    name=profile.provenance.sourceFile;
    assert(~isempty(regexp(name,'^[A-Za-z0-9_-]+\.json$','once')),'Invalid VVASP source filename.');
    fid=fopen(fullfile(folder,'experiments',name),'r');assert(fid>=0,'VVASP source record is missing.');
    cleanup=onCleanup(@() fclose(fid));raw=fread(fid,Inf,'*uint8');clear cleanup;paired=true;
else
    % Compatibility with previously exported local-only profile directories.
    file=fullfile(folder,[subject '.json']);if ~isfile(file),return;end
    profile=jsondecode(fileread(file));
end
assert(strcmp(profile.subject,subject),'Surgery plan belongs to another subject.');
if paired
    assert(~isempty(raw),'VVASP source record is empty.');
    assert(startsWith(profile.provenance.sourceFile,[subject '_']),'VVASP source filename belongs to another subject.');
    digest=java.security.MessageDigest.getInstance('SHA-256');digest.update(typecast(uint8(raw(:)),'int8'));
    hash=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
    assert(strcmpi(hash,profile.provenance.sourceSHA256), ...
        'VVASP source changed; regenerate its atlas labels before applying the surgery plan.');
end
profile.provenance.sourceDirectory=folder;
profile.provenance.sourceHost=host;
end
