classdef SpikeGL < handle
    % In-memory server used only for recording lifecycle failure tests.
    methods
        function s=SpikeGL(varargin)
            global ChipmunkSpikeGLTest
            if ChipmunkSpikeGLTest.connectFailure,error('Test:Connect','Server unavailable');end
        end
        function Close(s)
            global ChipmunkSpikeGLTest
            if isfield(ChipmunkSpikeGLTest,'closes'),ChipmunkSpikeGLTest.closes=ChipmunkSpikeGLTest.closes+1;end
        end
        function v=GetVersion(s),v='test server';end
        function v=GetDataDir(s,varargin),global ChipmunkSpikeGLTest;v=ChipmunkSpikeGLTest.dataDir;end
        function SetDataDir(s,~,v),global ChipmunkSpikeGLTest;ChipmunkSpikeGLTest.dataDir=v;end
        function v=GetRunName(s),global ChipmunkSpikeGLTest;v=ChipmunkSpikeGLTest.runName;end
        function SetRunName(s,v)
            global ChipmunkSpikeGLTest
            assert(ChipmunkSpikeGLTest.validated,'Run parameters never validated');
            ChipmunkSpikeGLTest.runName=v;
        end
        function v=IsRunning(s)
            global ChipmunkSpikeGLTest
            if isfield(ChipmunkSpikeGLTest,'polls'),ChipmunkSpikeGLTest.polls=ChipmunkSpikeGLTest.polls+1;end
            if isfield(ChipmunkSpikeGLTest,'pollFailure') && ChipmunkSpikeGLTest.pollFailure
                error('Test:Disconnected','Server connection lost');
            end
            v=ChipmunkSpikeGLTest.running;
        end
        function v=IsSaving(s)
            global ChipmunkSpikeGLTest
            if ChipmunkSpikeGLTest.pending > 0
                ChipmunkSpikeGLTest.pending=ChipmunkSpikeGLTest.pending-1;
            else
                ChipmunkSpikeGLTest.saving=ChipmunkSpikeGLTest.targetSaving;
            end
            v=ChipmunkSpikeGLTest.saving;
        end
        function p=GetParams(s)
            global ChipmunkSpikeGLTest
            if ~ChipmunkSpikeGLTest.validated,error('Test:Params','Run parameters never validated');end
            p=struct('snsRunName',ChipmunkSpikeGLTest.runName);
        end
        function SelectDevices(s,v,level)
            global ChipmunkSpikeGLTest
            assert(level==2);
            ChipmunkSpikeGLTest.detects=ChipmunkSpikeGLTest.detects+1;
            ChipmunkSpikeGLTest.devices=v;
            if ChipmunkSpikeGLTest.detectFailure,error('Test:Detect','Device detection failed');end
            assert(~ismember(ChipmunkSpikeGLTest.runName,ChipmunkSpikeGLTest.existingNames),'Run name already in use');
            ChipmunkSpikeGLTest.validated=true;
        end
        function v=GetProbeAddrs(s)
            global ChipmunkSpikeGLTest
            v='';tokens=regexp(ChipmunkSpikeGLTest.devices,'\((\d+),(\d+),(\d+)\)','tokens');
            for k=1:numel(tokens),v=[v '(' num2str(k-1) ',' strjoin(tokens{k},',') ')'];end
            if isempty(v),v='()';end
        end
        function v=GetOneBoxAddrs(s)
            global ChipmunkSpikeGLTest
            if isfield(ChipmunkSpikeGLTest,'addressFailure') && ChipmunkSpikeGLTest.addressFailure
                error('Test:Addresses','Device addresses unavailable');
            end
            v='';tokens=regexp(ChipmunkSpikeGLTest.devices,'\((\d+),obx\)','tokens');
            for k=1:numel(tokens),v=[v '(' num2str(k-1) ',' tokens{k}{1} ')'];end
            if isempty(v),v='()';end
        end
        function StartRun(s)
            global ChipmunkSpikeGLTest
            if ChipmunkSpikeGLTest.startFailure,error('Test:Start','Acquisition failed');end
            ChipmunkSpikeGLTest.starts=ChipmunkSpikeGLTest.starts+1;
            ChipmunkSpikeGLTest.running=true;
            ChipmunkSpikeGLTest.saving=ChipmunkSpikeGLTest.startSaves;
            ChipmunkSpikeGLTest.targetSaving=ChipmunkSpikeGLTest.startSaves;
            if isfield(ChipmunkSpikeGLTest,'afterStartDirectory')
                ChipmunkSpikeGLTest.dataDir=ChipmunkSpikeGLTest.afterStartDirectory;
            end
            if isfield(ChipmunkSpikeGLTest,'loseStartAck') && ChipmunkSpikeGLTest.loseStartAck
                error('Test:LostAck','Start acknowledgement lost');
            end
        end
        function SetRecordingEnable(s,v)
            global ChipmunkSpikeGLTest
            ChipmunkSpikeGLTest.enables=ChipmunkSpikeGLTest.enables+1;
            ChipmunkSpikeGLTest.targetSaving=logical(v);
            ChipmunkSpikeGLTest.pending=2;
        end
        function StopRun(s)
            global ChipmunkSpikeGLTest
            ChipmunkSpikeGLTest.stops=ChipmunkSpikeGLTest.stops+1;
            ChipmunkSpikeGLTest.running=false;
            ChipmunkSpikeGLTest.saving=false;
            ChipmunkSpikeGLTest.targetSaving=false;
            ChipmunkSpikeGLTest.pending=0;
        end
        function p=GetProbeList(s),global ChipmunkSpikeGLTest;p=ChipmunkSpikeGLTest.probeList;end
        function SetAnatomy_Pinpoint(s,v),global ChipmunkSpikeGLTest;ChipmunkSpikeGLTest.anatomy{end+1}=v;end
        function SetMetaData(s,v),global ChipmunkSpikeGLTest;ChipmunkSpikeGLTest.metadata=v;end
        function n=GetStreamNP(s,varargin),n=0;end
    end
end
