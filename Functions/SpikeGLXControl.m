function SpikeGLXControl(action)
% Control figure for the configured SpikeGLX host. Closing it leaves the run active.

    global BpodSystem

    if nargin < 1
        action = 'init';
    end

    switch lower(action)
        case 'init'
            initFigure();
            tryConnect();
            refreshFigure();
            startTraceTimer();
        case 'refresh'
            refreshFigure();
        case 'shutdown'
            stopTraceTimer();
            if hasFigure()
                delete(BpodSystem.GUIHandles.Figures.SpikeGLX);
            end
        otherwise
            error('SpikeGLXControl: unknown action %s', action);
    end


    function initFigure()
        state = spikeglx_client('get');
        if isfield(BpodSystem.GUIHandles, 'Figures') ...
                && isfield(BpodSystem.GUIHandles.Figures, 'SpikeGLX') ...
                && ishandle(BpodSystem.GUIHandles.Figures.SpikeGLX)
            figure(BpodSystem.GUIHandles.Figures.SpikeGLX);
            return
        end

        fig = figure( ...
            'Name', 'SpikeGLX', ...
            'NumberTitle', 'off', ...
            'MenuBar', 'none', ...
            'ToolBar', 'none', ...
            'Units', 'normalized', ...
            'Position', [0.02 0.08 0.34 0.86], ...
            'CloseRequestFcn', @closeFigure);
        if isempty(BpodSystem.GUIHandles)
            BpodSystem.GUIHandles = struct();
        end
        if ~isfield(BpodSystem.GUIHandles, 'Figures')
            BpodSystem.GUIHandles.Figures = struct();
        end
        BpodSystem.GUIHandles.Figures.SpikeGLX = fig;
        ha = struct();
        bg = get(fig, 'Color');

        ha.title = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 0.94 0.88 0.04], 'String', '', ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'left', 'BackgroundColor', bg);

        uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 0.89 0.16 0.035], 'String', 'Host', ...
            'HorizontalAlignment', 'left', 'BackgroundColor', bg);
        ha.host = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.24 0.89 0.46 0.04], 'String', state.host, ...
            'Callback', @(s,e) readFields());

        uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.72 0.89 0.10 0.035], 'String', 'TCP port', ...
            'HorizontalAlignment', 'left', 'BackgroundColor', bg);
        ha.port = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.82 0.89 0.12 0.04], 'String', num2str(state.port), ...
            'Callback', @(s,e) readFields());

        uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 0.84 0.18 0.035], 'String', 'Data root', ...
            'HorizontalAlignment', 'left', 'BackgroundColor', bg);
        ha.dataDir = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.24 0.84 0.70 0.04], 'String', state.dataDir, ...
            'Callback', @(s,e) readFields());

        uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 0.79 0.18 0.035], 'String', 'Run name', ...
            'HorizontalAlignment', 'left', 'BackgroundColor', bg);
        ha.runName = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.24 0.79 0.70 0.035], 'String', state.runName, ...
            'HorizontalAlignment', 'left', 'BackgroundColor', bg);

        ha.status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 0.74 0.88 0.04], 'String', 'disconnected', ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'left', 'BackgroundColor', bg);

        tabs = uitabgroup(fig,'Units','normalized','Position',[0.02 0.02 0.96 0.44]);
        devicesTab = uitab(tabs,'Title','Devices');
        neuralTab = uitab(tabs,'Title','Neural');
        analogTab = uitab(tabs,'Title','OneBox analog');
        digitalTab = uitab(tabs,'Title','Digital IO');
        anatomyTab = uitab(tabs,'Title','Anatomy');
        advancedTab = uitab(tabs,'Title','Advanced');
        ha.anatomyReload=uicontrol(anatomyTab,'Style','pushbutton','Units','normalized', ...
            'Position',[.66 .89 .30 .09],'String','Reload plan','Callback',@onAnatomyReload);
        ha.anatomyAxes=axes('Parent',anatomyTab,'Units','normalized','Position',[.16 .18 .80 .62]);
        title(ha.anatomyAxes,'No surgery plan loaded');
        ha.anatomyRegion=uicontrol(anatomyTab,'Style','text','Units','normalized', ...
            'Position',[.04 .02 .92 .10],'String','','HorizontalAlignment','left');
        ha.useSpikeGLX=uicontrol(devicesTab,'Style','checkbox','Units','normalized', ...
            'Position',[.04 .85 .92 .10],'String','Use current SpikeGLX selection', ...
            'Value',isempty(state.devices),'Callback',@onUseSpikeGLX);
        ha.deviceTable=uitable(devicesTab,'Units','normalized','Position',[.04 .15 .92 .68], ...
            'Data',spikeglxDeviceRows(state.devices),'ColumnName',{'Record','Slot','Port','Dock'}, ...
            'ColumnFormat',{'logical','numeric',{'1','2','3','4','XIO'},'numeric'}, ...
            'ColumnEditable',[true true true true],'RowName',[], ...
            'ColumnWidth',{55 55 65 55},'CellEditCallback',@onDeviceEdit);
        ha.connect = uicontrol(advancedTab, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.06 0.48 0.26 0.12], 'String', 'Connect', ...
            'Callback', @onConnect);
        ha.start = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.06 0.67 0.88 0.055], 'String', 'Prepare recording', ...
            'Callback', @onPrepare);
        ha.enable = uicontrol(advancedTab, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.36 0.48 0.27 0.12], 'String', 'Enable recording', ...
            'Callback', @onEnable);
        ha.disable = uicontrol(advancedTab, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.67 0.48 0.27 0.12], 'String', 'Disable recording', ...
            'Callback', @onDisable);
        ha.stop = uicontrol(advancedTab, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.06 0.27 0.88 0.12], 'String', 'Stop acquisition', ...
            'Callback', @onStop);

        ha.actionLog=uicontrol(fig,'Style','listbox','Units','normalized', ...
            'Position',[.06 .55 .88 .105],'String',{},'FontSize',9, ...
            'TooltipString','Timestamped actions and failures for this session');
        ha.anatomy = uicontrol(advancedTab,'Style','text','Units','normalized', ...
            'Position',[.06 .65 .88 .15],'String',state.anatomyStatus,'HorizontalAlignment','left');
        uicontrol(advancedTab,'Style','text','Units','normalized', ...
            'Position',[.06 .13 .28 .10],'String','VVASP folder on host','HorizontalAlignment','left');
        ha.anatomyDir=uicontrol(advancedTab,'Style','edit','Units','normalized', ...
            'Position',[.35 .13 .59 .10],'String',state.anatomyDir,'Callback',@(s,e) readFields());
        ha.error = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 0.465 0.88 0.065], 'String', '', ...
            'HorizontalAlignment', 'left', 'ForegroundColor', [0.7 0 0], ...
            'BackgroundColor', bg);

        ha.imec = axes('Parent', neuralTab, 'Units', 'normalized', ...
            'Position', [0.14 0.16 0.80 0.74]);
        title(ha.imec, 'imec');
        ylabel(ha.imec, 'channel');

        ha.obx = axes('Parent', analogTab, 'Units', 'normalized', ...
            'Position', [0.14 0.16 0.80 0.74]);
        title(ha.obx, 'OneBox');
        xlabel(ha.obx, 'time (s)');
        ha.digital = axes('Parent', digitalTab,'Units','normalized', ...
            'Position',[0.22 0.14 0.73 0.78]);
        tabs.SelectedTab = devicesTab;

        BpodSystem.GUIHandles.SpikeGLX = ha;
    end


    function tryConnect()
        if ~readFields(),return;end
        state=spikeglx_client('connect');
        if ~state.running,spikeglx_client('loadanatomy');end
    end


    function refreshFigure()
        if ~hasFigure()
            return
        end
        state = spikeglx_client('refresh');
        ha = BpodSystem.GUIHandles.SpikeGLX;
        title=sprintf('SpikeGLX on %s:%d',state.host,state.port);
        set(BpodSystem.GUIHandles.Figures.SpikeGLX,'Name',title);
        set(ha.title,'String',title);
        if state.running,editable='off';else,editable='on';end
        set([ha.host ha.port ha.dataDir ha.useSpikeGLX ha.anatomyDir ha.anatomyReload],'Enable',editable);
        set(ha.deviceTable,'Enable',editable);
        if get(ha.useSpikeGLX,'Value') && ~isempty(state.remoteDevices)
            set(ha.deviceTable,'Data',spikeglxDeviceRows(state.remoteDevices));
        end
        if ~isequal(get(ha.actionLog,'String'),state.actionLog(:))
            set(ha.actionLog,'String',state.actionLog,'Value',max(1,numel(state.actionLog)), ...
                'ListboxTop',max(1,numel(state.actionLog)-4));
        end
        if isempty(strtrim(get(ha.dataDir,'String')))
            set(ha.dataDir,'String',state.dataDir);
        end
        set(ha.runName, 'String', state.runName);
        set(ha.status, 'String', statusText(state), 'ForegroundColor', statusColor(state), ...
            'TooltipString',state.version);
        set(ha.anatomy,'String',['Surgery-plan overlay: ' state.anatomyStatus], ...
            'TooltipString',state.anatomyStatus);
        renderAnatomy(ha,state);
        set(ha.error, 'String', state.lastError,'TooltipString',state.lastError);
        if isfield(BpodSystem.GUIHandles,'DemonStartButton') && ...
                isgraphics(BpodSystem.GUIHandles.DemonStartButton) && ...
                strcmp(get(BpodSystem.GUIHandles.DemonStartButton,'String'),'Start session')
            ready=state.connected && state.running && state.ownedRun && ~state.startPending && ...
                strcmp(state.remoteRunName,state.runName) && isempty(state.lastError);
            if ready, enabled='on';else, enabled='off';end
            set(BpodSystem.GUIHandles.DemonStartButton,'Enable',enabled);
        end
    end


    function onConnect(~, ~)
        tryConnect();
        refreshFigure();
    end

    function onAnatomyReload(~,~)
        if readFields(),spikeglx_client('loadanatomy');end
        refreshFigure();
    end

    function renderAnatomy(ha,state)
        if ~isequal(ha.anatomyAxes.UserData,state.anatomyProfile)
            cla(ha.anatomyAxes);set(ha.anatomyRegion,'String','');
            if ~isempty(state.anatomyProfile)
                try
                    plotSpikeGLXSurgeryPlan(ha.anatomyAxes,state.anatomyProfile,@onAnatomySelect);
                catch ME
                    title(ha.anatomyAxes,'Plan preview unavailable');
                    set(ha.anatomyRegion,'String',ME.message);
                end
            end
            ha.anatomyAxes.UserData=state.anatomyProfile;
        end
        if isempty(state.anatomyProfile)
            title(ha.anatomyAxes,state.anatomyStatus,'Interpreter','none');
            set(ha.anatomyAxes,'XTick',[],'YTick',[]);ylabel(ha.anatomyAxes,'');
        end
    end

    function onAnatomySelect(shank,region)
        ha=BpodSystem.GUIHandles.SpikeGLX;
        set(ha.anatomyRegion,'String',sprintf('Shank %d | %s | %.0f–%.0f µm from tip', ...
            shank,region.region,region.startUm,region.endUm));
    end


    function onPrepare(~, ~)
        if ~readFields(),refreshFigure();return;end
        ha=BpodSystem.GUIHandles.SpikeGLX;
        if ~get(ha.useSpikeGLX,'Value') && isempty(spikeglxDeviceSelection(get(ha.deviceTable,'Data')))
            spikeglx_client('set','lastError','Select at least one probe dock or XIO.');
            spikeglx_client('log','Prepare rejected: no devices selected');
            refreshFigure();return
        end
        spikeglx_client('prepare');
        refreshFigure();
    end


    function onEnable(~, ~)
        if ~readFields(),refreshFigure();return;end
        state = spikeglx_client('enable');
        if state.recording && state.ownedRun && isempty(state.lastError)
            [ok,message]=labcams_ephys('start');
            if ~ok
                spikeglx_client('disable');
                spikeglx_client('set','lastError',message);spikeglx_client('log',message);
            end
        end
        refreshFigure();
    end


    function onDisable(~, ~)
        spikeglx_client('disable');
        [ok,message]=labcams_ephys('stop');
        if ~ok,spikeglx_client('log',message);warning('chipmunk_solo:CameraStop','%s',message);end
        refreshFigure();
    end


    function onStop(~, ~)
        spikeglx_client('stop');
        [ok,message]=labcams_ephys('stop');
        if ~ok,spikeglx_client('log',message);warning('chipmunk_solo:CameraStop','%s',message);end
        refreshFigure();
    end


    function valid = readFields()
        valid=false;
        if ~hasFigure()
            return
        end
        ha = BpodSystem.GUIHandles.SpikeGLX;
        try
            devices='';
            if ~get(ha.useSpikeGLX,'Value'),devices=spikeglxDeviceSelection(get(ha.deviceTable,'Data'));end
            port=str2double(get(ha.port,'String'));
            assert(isscalar(port) && isfinite(port) && port==fix(port) && port>=1 && port<=65535, ...
                'Port must be an integer from 1 to 65535.');
        catch ME
            spikeglx_client('set','lastError',ME.message);return
        end
        spikeglx_client('set', 'host', get(ha.host, 'String'));
        spikeglx_client('set', 'port', port);
        spikeglx_client('set', 'dataDir', get(ha.dataDir, 'String'));
        spikeglx_client('set', 'devices', devices);
        spikeglx_client('set', 'anatomyDir', get(ha.anatomyDir, 'String'));
        valid=true;
    end

    function onDeviceEdit(~,~)
        ha=BpodSystem.GUIHandles.SpikeGLX;
        set(ha.useSpikeGLX,'Value',0);
        if readFields(),spikeglx_client('set','lastError','');end
        refreshFigure();
    end

    function onUseSpikeGLX(~,~)
        readFields();refreshFigure();
    end


    function startTraceTimer()
        stopTraceTimer();
        t = timer( ...
            'Name', 'SpikeGLXTraces', ...
            'Period', 0.5, ...
            'ExecutionMode', 'fixedSpacing', ...
            'TimerFcn', @(~,~) updateTraces());
        BpodSystem.GUIHandles.SpikeGLX.traceTimer = t;
        start(t);
    end


    function stopTraceTimer()
        if isfield(BpodSystem.GUIHandles, 'SpikeGLX') ...
                && isfield(BpodSystem.GUIHandles.SpikeGLX, 'traceTimer')
            t = BpodSystem.GUIHandles.SpikeGLX.traceTimer;
            if ~isempty(t) && isvalid(t)
                stop(t);
                delete(t);
            end
            BpodSystem.GUIHandles.SpikeGLX.traceTimer = [];
        end
        leftover = timerfind('Name', 'SpikeGLXTraces');
        if ~isempty(leftover)
            stop(leftover);
            delete(leftover);
        end
    end


    function updateTraces()
        if ~hasFigure()
            stopTraceTimer();
            return
        end
        refreshFigure();
        ha = BpodSystem.GUIHandles.SpikeGLX;
        traces = spikeglx_client('traces');
        if isfield(ha, 'imec') && ishandle(ha.imec)
            drawImec(ha.imec, traces);
        end
        if isfield(ha, 'obx') && ishandle(ha.obx)
            drawOneBox(ha.obx, traces);
        end
        drawDigital(ha.digital,traces);
    end

    function drawImec(ax, traces)
        cla(ax);
        if ~traces.ok || isempty(traces.imec)
            title(ax, traces.error);
            ylabel(ax, 'channel');
            return
        end
        data = [];
        t = traces.imec(1).t;
        labels = {};
        for i = 1:numel(traces.imec)
            d = traces.imec(i).data;
            d = d - median(d, 1);
            data = [data, d]; %#ok<AGROW>
            labels{end+1} = traces.imec(i).label; %#ok<AGROW>
        end
        sigma = std(data, 0, 1);
        sigma(sigma == 0) = 1;
        data = data ./ sigma;
        imagesc(ax, t, 1:size(data, 2), data');
        set(ax, 'YDir', 'normal');
        set(ax, 'CLim', [-4 4]);
        colormap(ax, gray);
        ylabel(ax, 'channel');
        title(ax, strjoin(labels, '  |  '));
        xlim(ax, [0 max(t(end), eps)]);
    end

    function drawOneBox(ax, traces)
        cla(ax);
        if ~traces.ok || isempty(traces.obx)
            title(ax, 'OneBox');
            return
        end
        analog = traces.obx.channels < traces.obx.nXA;
        if ~any(analog)
            title(ax,'No analog inputs acquired');
            return
        end
        d = traces.obx.data(:,analog);
        t = traces.obx.t;
        chans = traces.obx.channels(analog);
        d = d - median(d, 1);
        scale = max(std(d, 0, 1));
        if scale == 0
            scale = 1;
        end
        hold(ax, 'on');
        nChan = size(d, 2);
        for c = 1:nChan
            plot(ax, t, d(:, c) / scale + (c - 1) * 4, 'k');
            text(ax, t(1), (c - 1) * 4, sprintf('  ch %d', chans(c)), ...
                'VerticalAlignment', 'bottom', 'FontSize', 8);
        end
        hold(ax, 'off');
        xlim(ax, [0 max(t(end), eps)]);
        ylim(ax, [-3, max(nChan - 1, 0) * 4 + 3]);
        set(ax, 'YTick', []);
        xlabel(ax, 'time (s)');
        title(ax, 'OneBox analog inputs');
    end

    function drawDigital(ax,traces)
        cla(ax);
        if ~traces.ok || isempty(traces.obx)
            title(ax,traces.error);
            return
        end
        [levels,labels] = oneBoxDigitalLines(traces.obx);
        if isempty(levels)
            title(ax,'No digital inputs acquired');
            return
        end
        offsets = 2*(0:size(levels,2)-1);
        stairs(ax,traces.obx.t,double(levels)+offsets,'LineWidth',1);
        set(ax,'YTick',offsets+.5,'YTickLabel',labels,'YDir','normal', ...
            'YLim',[-.5 offsets(end)+1.5],'FontSize',8);
        xlim(ax,[0 max(traces.obx.t(end),eps)]);
        grid(ax,'on');
        xlabel(ax,'time (s)');
        title(ax,'Digital inputs: low / high');
    end

    function closeFigure(~, ~)
        stopTraceTimer();
        if hasFigure()
            delete(BpodSystem.GUIHandles.Figures.SpikeGLX);
        end
    end


    function ok = hasFigure()
        ok = isfield(BpodSystem.GUIHandles, 'Figures') ...
            && isfield(BpodSystem.GUIHandles.Figures, 'SpikeGLX') ...
            && ishandle(BpodSystem.GUIHandles.Figures.SpikeGLX);
    end
end


function textOut = statusText(state)
    if ~state.connected
        textOut = 'SpikeGLX network: disconnected';
    elseif state.running && ~state.ownedRun
        textOut = sprintf('SpikeGLX network: connected\nExternal acquisition — task start blocked');
    elseif state.recording
        textOut = sprintf('SpikeGLX network: connected\nAcquisition: running | Recording: ON');
    elseif state.running
        textOut = sprintf('SpikeGLX network: connected\nAcquisition: running | Recording: OFF');
    else
        textOut = sprintf('SpikeGLX network: connected\nAcquisition: stopped | Recording: OFF');
    end
end


function colorOut = statusColor(state)
    if state.recording
        colorOut = [0.10 0.45 0.10];
    elseif state.running
        colorOut = [0.15 0.35 0.70];
    elseif state.connected
        colorOut = [0.15 0.15 0.15];
    else
        colorOut = [0.70 0.15 0.10];
    end
end
