function result = spikeglx_client(cmd, varargin)
% Persistent SpikeGLX TCP client used by the ephys protocol GUI.
%
% Commands:
%   init(runName,subject,session) store the Bpod session identity
%   set(field, value)      host | port | dataDir | runName
%   get                    return the status struct
%   connect                open TCP to the configured host
%   start                  SetDataDir (if set), SetRunName, StartRun
%   enable                 SetRecordingEnable(1)
%   disable                SetRecordingEnable(0)
%   stop                   StopRun
%   refresh                poll IsRunning / IsSaving / GetRunName
%   traces                 latest AP or OneBox snippets for the figure
%   shutdown               disable if saving, stop if running, close TCP
%
% Connect failure is stored in lastError; it does not throw.

    persistent hSGL state

    if isempty(state)
        state = defaultState();
        state = loadPrefs(state);
    end

    result = [];
    cmd = lower(cmd);

    switch cmd
        case 'init'
            if ~isempty(varargin)
                state.runName = varargin{1};
                state.ownedRun = false;state.startPending=false;
                if numel(varargin)>1, state.subject=varargin{2};else, state.subject='';end
                if numel(varargin)>2,state.session=varargin{3};else,state.session='';end
                state.sessionDir='';state.actionLog={};
                state.lastError='';
                state.anatomyApplied=false;state.anatomyProvenance=struct();
                state.anatomyProfile=[];
                state.anatomyStatus='Anatomy off';
            end
            result = state;

        case 'set'
            fieldName = varargin{1};
            value = varargin{2};
            if ~isfield(state, fieldName)
                error('spikeglx_client: unknown field %s', fieldName);
            end
            if any(strcmp(fieldName,{'host','port'})) && ~isequal(state.(fieldName),value)
                state=doRefresh(state);
                if state.running || (~state.connected && (state.ownedRun || state.startPending))
                    state.lastError='Confirm acquisition is stopped before changing the connection.';result=state;return
                end
                state=closeHandle(state);
                state.sessionDir='';state.ownedRun=false;state.startPending=false;
            end
            if strcmp(fieldName,'dataDir') && ~isequal(state.dataDir,value)
                state=doRefresh(state);
                if state.running || (~state.connected && (state.ownedRun || state.startPending))
                    state.lastError='Confirm acquisition is stopped before changing the recording folder.';result=state;return
                end
                state.sessionDir='';
            end
            if strcmp(fieldName,'anatomyDir') && state.running && ~isequal(state.anatomyDir,value)
                state.lastError='Stop acquisition before changing the surgery-plan source.';result=state;return
            end
            if any(strcmp(fieldName,{'host','anatomyDir'})) && ~isequal(state.(fieldName),value)
                state.anatomyProfile=[];state.anatomyApplied=false;state.anatomyProvenance=struct();
                state.anatomyStatus='Surgery plan not loaded';
            end
            state.(fieldName) = value;
            savePrefs(state);
            result = state;

        case 'get'
            result = state;

        case 'log'
            state=logAction(state,varargin{1});result=state;

        case 'connect'
            state = doConnect(state);
            result = state;

        case 'loadanatomy'
            if state.running
                state=logAction(state,'Stop acquisition before reloading the surgery plan.');
            else
                state=loadAnatomy(state);
                state=logAction(state,state.anatomyStatus);
            end
            result=state;

        case 'prepare'
            state = doPrepare(state);
            result = state;

        case 'begin'
            state = doBegin(state);
            result = state;

        case 'start'
            state = doStart(state);
            result = state;

        case 'enable'
            state = doEnable(state, 1);
            result = state;

        case 'disable'
            state = doEnable(state, 0);
            result = state;

        case 'stop'
            state = doStop(state);
            result = state;

        case 'refresh'
            state = doRefresh(state);
            result = state;

        case 'traces'
            result = doTraces();

        case 'shutdown'
            state = doShutdown(state);
            hSGL = [];
            result = state;

        otherwise
            error('spikeglx_client: unknown command %s', cmd);
    end
    if any(strcmp(cmd,{'init','connect','prepare','begin','start','enable','disable','stop','shutdown'}))
        if ~isempty(state.lastError)
            message=[cmd ' failed: ' state.lastError];
        else
            switch cmd
                case 'init',message=['Session initialized: ' state.runName];
                case 'connect',message=sprintf('Connected to %s:%d',state.host,state.port);
                case 'prepare'
                    flags={'OFF','ON'};
                    message=sprintf('Prepared: acquisition %s; recording %s',flags{1+state.running},flags{1+state.recording});
                case 'begin',message='Recording confirmed; starting task';
                case 'start',message=sprintf('Acquisition started; recording=%d',state.recording);
                case 'enable',message='Recording enabled';
                case 'disable',message='Recording disabled';
                otherwise
                    if state.running,message='Connection closed; external acquisition left active';
                    else,message='Acquisition and recording stopped';end
            end
        end
        state=logAction(state,message);result=state;
    end

    function state = logAction(state,message)
        state.actionLog{end+1}=sprintf('%s  %s',datestr(now,'HH:MM:SS'),message);
        state.actionLog=state.actionLog(max(1,end-199):end);
    end

    function state = prepareFolder(state)
        if ~isempty(state.session) && isempty(state.sessionDir)
            state.sessionDir=ensureSpikeGLXSessionFolder(state.dataDir,state.subject,state.session,state.host);
            state=logAction(state,['Save folder: ' state.sessionDir]);
        end
    end

    function folder = recordingFolder(state)
        folder=state.dataDir;
        if ~isempty(state.sessionDir),folder=state.sessionDir;end
    end

    function state = doConnect(state)
        state = closeHandle(state);
        try
            hSGL = SpikeGL(state.host, state.port);
            state.connected = true;
            state.lastError = '';
            state.version = char(GetVersion(hSGL));
            if isempty(state.dataDir)
                state.dataDir = char(GetDataDir(hSGL, 0));
            end
            state = doRefresh(state);
            if state.connected,state.remoteDevices=readDeviceSelection();end
            savePrefs(state);
        catch ME
            state = closeHandle(state);
            state.running = false;
            state.recording = false;
            state.lastError = ME.message;
        end
    end

    function state = doPrepare(state)
        state = ensureConnected(state);
        if ~state.connected, return; end
        state = doRefresh(state);
        if ~state.connected, return; end
        if state.running
            if ~state.ownedRun || ~strcmp(state.remoteRunName,state.runName)
                state.lastError = 'Another SpikeGLX run is active. Leave it running and resolve its ownership first.';
            else
                state.lastError = '';
                if state.startPending
                    state=doEnable(state,0);
                    if isempty(state.lastError),state.startPending=false;end
                end
            end
            return
        end
        try
            assert(~isempty(state.runName),'Start the Bpod protocol before preparing recording.');
            state=prepareFolder(state);
            if ~isempty(state.dataDir),SetDataDir(hSGL,0,recordingFolder(state));end
            try,params=GetParams(hSGL);if ~isempty(fieldnames(params)),SetRunName(hSGL,state.runName);end;catch,end
            % SpikeGLX only starts runs on settings verified against the attached hardware.
            assert(~isempty(state.devices),'Select at least one probe dock or XIO.');
            SelectDevices(hSGL,state.devices,2); % Detect + Verify | Save
            state.remoteDevices=readDeviceSelection();
            state=logAction(state,['Devices verified: ' state.devices]);
        catch ME
            state.lastError = ['Recording setup is not ready: ' ME.message];
            return
        end
        state = doStart(state);
        if isempty(state.lastError)
            state = waitForState(state,true,[]);
            if state.running && state.recording
                state = doEnable(state,0);
            end
            if isempty(state.lastError),state.startPending=false;state=doAnatomy(state);end
        end
    end

    function state = loadAnatomy(state)
        state.anatomyApplied=false;state.anatomyProvenance=struct();
        state.anatomyProfile=[];
        if isempty(state.anatomyDir) || isempty(state.subject)
            state.anatomyStatus='No surgery plan selected';return
        end
        try
            profile=loadSpikeGLXSurgeryPlan(state.anatomyDir,state.subject,state.host);
            if isempty(profile),state.anatomyStatus=['No surgery plan for ' state.subject];return;end
            state.anatomyProfile=profile;
            state.anatomyStatus=['Plan loaded: ' state.subject];
        catch ME
            state.anatomyStatus=['Plan unavailable: ' ME.message];
        end
    end

    function state = doAnatomy(state)
        state=loadAnatomy(state);
        if isempty(state.anatomyProfile),return;end
        profile=state.anatomyProfile;
        try
            commands=vvaspAnatomyCommands(profile,char(GetProbeList(hSGL)),state.subject);
            for k=1:numel(commands),SetAnatomy_Pinpoint(hSGL,commands{k});end
            SetMetaData(hSGL,struct('chipmunk_anatomy_kind','surgery plan', ...
                'chipmunk_anatomy_source',profile.provenance.sourceFile, ...
                'chipmunk_anatomy_sha256',profile.provenance.sourceSHA256));
            state.anatomyApplied=true;state.anatomyProvenance=profile.provenance;
            state.anatomyStatus=['Plan applied to SpikeGLX: ' state.subject];
        catch ME
            state.anatomyStatus=['Anatomy not applied: ' ME.message];
        end
    end

    function selection = readDeviceSelection()
        selection='';
        try
            probes=regexp(char(GetProbeAddrs(hSGL)),'\((\d+),(\d+),(\d+),(\d+)\)','tokens');
            boxes=regexp(char(GetOneBoxAddrs(hSGL)),'\((\d+),(\d+)\)','tokens');
            for k=1:numel(probes)
                p=probes{k};selection=[selection '(' strjoin(p(2:4),',') ')']; %#ok<AGROW>
            end
            for k=1:numel(boxes)
                selection=[selection '(' boxes{k}{2} ',obx)']; %#ok<AGROW>
            end
        catch
            selection=''; % A partial address query must never authorize configuration reuse.
        end
    end

    function state = doBegin(state)
        state = doRefresh(state);
        if ~state.connected || ~state.running || state.startPending
            state.lastError = 'Prepare recording before starting the session.';
            return
        end
        if ~state.ownedRun || ~strcmp(state.remoteRunName,state.runName)
            state.lastError = 'The active SpikeGLX run was not prepared by this Bpod session.';
            return
        end
        if state.recording
            state.lastError = '';
            return
        end
        state = doEnable(state,1);
    end

    function state = waitForState(state,running,recording)
        started = tic;
        while toc(started) < 5
            state = doRefresh(state);
            if ~state.connected, return; end
            if state.running == running && (isempty(recording) || state.recording == recording)
                return
            end
            pause(.05);
        end
        state.lastError = 'SpikeGLX did not confirm the requested recording state within 5 seconds.';
    end

    function state = doStart(state)
        state = ensureConnected(state);
        if ~state.connected
            return
        end
        try
            if IsRunning(hSGL)
                state.lastError = 'SpikeGLX is already running.';
                state = doRefresh(state);
                return
            end
            if ~isempty(state.dataDir)
                state=prepareFolder(state);
                SetDataDir(hSGL, 0, recordingFolder(state));
            end
            if isempty(state.runName)
                error('Run name is empty. Start the Bpod protocol first.');
            end
            SetRunName(hSGL, state.runName);
            % Keep the expected session identity if acquisition starts but its reply is lost.
            state.startPending=true;
            StartRun(hSGL);
            state.ownedRun = true;state.startPending=false;
            state.lastError = '';
            state = doRefresh(state);
            savePrefs(state);
        catch ME
            message=ME.message;
            if state.startPending
                state=doConnect(state);
                if state.connected && state.running && state.ownedRun
                    state.lastError='';return
                end
            end
            state.lastError = message;
        end
    end

    function state = doEnable(state, flag)
        state = ensureConnected(state);
        if ~state.connected
            return
        end
        try
            if ~IsRunning(hSGL)
                error('SpikeGLX is not acquiring. Start acquisition first.');
            end
            state = doRefresh(state);
            if ~state.ownedRun || ~strcmp(state.remoteRunName,state.runName)
                error('This Bpod session does not own the active SpikeGLX run.');
            end
            SetRecordingEnable(hSGL, flag);
            state.lastError = '';
            state = waitForState(state,true,logical(flag));
        catch ME
            state.lastError = ME.message;
        end
    end

    function state = doStop(state)
        state = doRefresh(state);
        if state.running && (~state.ownedRun || ~strcmp(state.remoteRunName,state.runName))
            state.lastError = 'This Bpod session does not own the active SpikeGLX run.';
            return
        end
        if ~isValidHandle()
            state.connected = false;
            state.running = false;
            state.recording = false;
            return
        end
        try
            if IsSaving(hSGL)
                SetRecordingEnable(hSGL, 0);
            end
        catch ME
            state.lastError = ME.message;
        end
        try
            if IsRunning(hSGL)
                StopRun(hSGL);
            end
            state.lastError = '';
            state = waitForState(state,false,false);
            if state.connected && ~state.running && ~state.recording, state.ownedRun = false;state.startPending=false; end
        catch ME
            state.lastError = ME.message;
        end
    end

    function state = doRefresh(state)
        if ~isValidHandle()
            state.connected = false;
            state.running = false;
            state.recording = false;
            return
        end
        try
            state.connected = true;
            state.running = logical(IsRunning(hSGL));
            state.recording = logical(IsSaving(hSGL));
            assert(isscalar(state.running) && isscalar(state.recording), ...
                'SpikeGLX returned an invalid acquisition status.');
        catch ME
            state = closeHandle(state);
            state.running = false;
            state.recording = false;
            state.lastError = ME.message;
            state = logAction(state,['Connection lost: ' ME.message ...
                '. Check acquisition on the recording host, then reconnect.']);
            return
        end
        try
            state.remoteRunName = char(GetRunName(hSGL));
            state.remoteDataDir = char(GetDataDir(hSGL,0));
            if state.startPending
                state.ownedRun=state.running && ~isempty(state.sessionDir) && ...
                    strcmp(state.remoteRunName,state.runName) && ...
                    strcmpi(normalizeFolder(state.remoteDataDir),normalizeFolder(state.sessionDir));
                if ~state.running || ~state.ownedRun,state.startPending=false;end
            end
            if state.running && state.ownedRun && ...
                    (~strcmp(state.remoteRunName,state.runName) || ...
                    ~strcmpi(normalizeFolder(state.remoteDataDir),normalizeFolder(recordingFolder(state))))
                state.ownedRun=false;
            end
        catch ME
            state.remoteRunName = '';
            if ~contains(ME.message, 'never validated')
                state = closeHandle(state);
                state.lastError = ME.message;
            end
        end
    end

    function folder = normalizeFolder(folder)
        folder=regexprep(strrep(folder,'\','/'),'/+$','');
    end

    function state = doShutdown(state)
        if state.ownedRun || state.startPending
            state=doRefresh(state);
            if ~state.connected,state=doConnect(state);end
            if state.connected
                state=doStop(state);
            else
                state.lastError=['Could not confirm acquisition stopped. Check SpikeGLX on ' state.host '. ' state.lastError];
            end
        end
        state = closeHandle(state);
    end

    function state = ensureConnected(state)
        if isValidHandle()
            state.connected = true;
            return
        end
        state = doConnect(state);
    end

    function state = closeHandle(state)
        if isValidHandle()
            try
                Close(hSGL);
            catch
            end
        end
        hSGL = [];
        state.connected = false;
    end

    function ok = isValidHandle()
        ok = ~isempty(hSGL) && isobject(hSGL);
    end

    function result = doTraces()
        result = struct('ok', false, 'imec', [], 'obx', [], ...
            'error', 'start acquisition to see traces');
        if ~isValidHandle()
            result.error = 'disconnected';
            return
        end
        try
            if ~IsRunning(hSGL)
                return
            end
        catch ME
            state = closeHandle(state);
            state.lastError = ME.message;
            result.error = 'disconnected';
            return
        end
        try
            result.imec = fetchImec();
            result.obx = fetchOneBox();
            if isempty(result.imec) && isempty(result.obx)
                result.error = 'no imec or OneBox streams';
                return
            end
            result.ok = true;
            result.error = '';
        catch ME
            result.error = ME.message;
        end
    end

    function streams = fetchImec()
        streams = [];
        nIm = GetStreamNP(hSGL, 2);
        for ip = 0:nIm-1
            counts = GetStreamAcqChans(hSGL, 2, ip);
            nAP = counts(1);
            if isempty(nAP) || nAP < 1
                continue
            end
            chans = savedOrRange(2, ip, nAP);
            next = fetchStream(2, ip, chans, sprintf('imec%d AP  %d ch', ip, numel(chans)));
            if isempty(next)
                continue
            end
            if isempty(streams)
                streams = next;
            else
                streams(end+1, 1) = next;
            end
        end
    end

    function stream = fetchOneBox()
        stream = [];
        nOb = GetStreamNP(hSGL, 1);
        if nOb < 1
            return
        end
        counts = GetStreamAcqChans(hSGL, 1, 0);
        nXA = counts(1);
        nDW = 0;
        if numel(counts) > 1
            nDW = counts(2);
        end
        nUse = sum(counts);
        if isempty(nUse) || nUse < 1
            return
        end
        chans = 0:nUse-1; % Monitor all acquired inputs, even if saving a subset.
        stream = fetchStream(1, 0, chans, sprintf('OneBox  %d ch', numel(chans)));
        if ~isempty(stream)
            stream.nXA = nXA;
            stream.nDW = nDW;
            stream.nSY = counts(3);
            if nXA > 0
                stream.toVolts = GetStreamI16ToVolts(hSGL, 1, 0, 0);
                [stream.vMin, stream.vMax] = GetStreamVoltageRange(hSGL, 1, 0);
            end
        end
    end

    function chans = savedOrRange(js, ip, nKeep)
        chans = GetStreamSaveChans(hSGL, js, ip);
        if isempty(chans)
            chans = 0:nKeep-1;
        else
            chans = chans(chans < nKeep);
            if isempty(chans)
                chans = 0:nKeep-1;
            end
        end
        chans = chans(:)';
    end

    function stream = fetchStream(js, ip, chans, label)
        fs = GetStreamSampleRate(hSGL, js, ip);
        ds = max(1, round(fs / 1000));
        if js == 1
            ds = 1; % Keep short digital pulses visible.
        end
        nSamps = max(1, round(0.3 * fs));
        mat = FetchLatest(hSGL, js, ip, nSamps, chans, ds);
        stream = [];
        if isempty(mat)
            return
        end
        stream = struct();
        stream.data = double(mat);
        stream.t = (0:size(mat, 1) - 1)' * (ds / fs);
        stream.channels = chans;
        stream.label = label;
    end
end


function state = defaultState()
    state = struct( ...
        'host', 'jupiter.local', ...
        'port', 4142, ...
        'dataDir', '', ...
        'devices', '', ...
        'remoteDevices', '', ...
        'subject', '', ...
        'session', '', ...
        'sessionDir', '', ...
        'actionLog', {{}}, ...
        'anatomyDir', 'D:/VVASP', ...
        'anatomyStatus', 'Anatomy off', ...
        'anatomyApplied', false, ...
        'anatomyProvenance', struct(), ...
        'anatomyProfile', [], ...
        'runName', '', ...
        'remoteRunName', '', ...
        'remoteDataDir', '', ...
        'version', '', ...
        'connected', false, ...
        'running', false, ...
        'recording', false, ...
        'ownedRun', false, ...
        'startPending', false, ...
        'lastError', '');
end


function prefsPath = prefsFile()
    prefsPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'spikeglx_prefs.mat');
end


function state = loadPrefs(state)
    pathName = prefsFile();
    if exist(pathName, 'file') ~= 2
        return
    end
    loaded = load(pathName);
    if isfield(loaded, 'host')
        state.host = loaded.host;
    end
    if isfield(loaded, 'port')
        state.port = loaded.port;
    end
    if isfield(loaded,'anatomyDir')
        state.anatomyDir=loaded.anatomyDir;
        if startsWith(state.anatomyDir,'/home/anne/chipmunk-anatomy/')
            state.anatomyDir='D:/VVASP';
        end
    end
    if isfield(loaded, 'devices')
        state.devices = loaded.devices;
    end
    if isfield(loaded, 'dataDir')
        state.dataDir = loaded.dataDir;
    end
end


function savePrefs(state)
    host = state.host;
    port = state.port;
    dataDir = state.dataDir;
    devices = state.devices;
    anatomyDir = state.anatomyDir;
    try
        save(prefsFile(), 'host', 'port', 'dataDir', 'devices', 'anatomyDir');
    catch
    end
end
