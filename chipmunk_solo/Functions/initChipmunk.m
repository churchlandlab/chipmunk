function S = initChipmunk;
% Collect solo-subject metadata and create the session output path.
global BpodSystem
%% Gather additional user input and generate file structure
%Extract the info about the experiment from the settings name (that has
%magically been copied into the subjects folder structure).
settingsPathPieces = split(BpodSystem.Path.Settings, filesep);
experimentName = settingsPathPieces{end}(1:end-4); %get the name to identify the settings. Probaly this is the most stable feature...
selectedSubjName = settingsPathPieces{end-3}; %Retrieve the name of the mouse, this is possible because the settings file is copied over to the animal's folder

%Launch an additional GUI to incorporate more info
ensureOptionalRecordingSettings();
initPanel = figure('Units','Normal','Position',[0.4, 0.2, 0.3, 0.5],'Name',experimentName,...
    'NumberTitle','off','MenuBar','none','Tag','ChipmunkInit','Visible','off');
initCleanup = onCleanup(@() deleteIfValid(initPanel));
ha = struct(); %define empty struct for ui handles
userInput = struct();

%Generating the different UI panels to group the user inputs
Demon = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.75, 2/3, 0.25],'Title','Demonstrator','FontWeight','bold');
Setup = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.5, 2/3, 0.25],'Title','Setup','FontWeight','bold');
Labcams = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.25, 2/3, 0.25],'Title','Labcams','FontWeight','bold');
Ephys = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0, 2/3, 0.25],'Title','Ephys','FontWeight','bold');

%Pasting the descriptions to the user input fields
uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style', 'text', 'String','Demonstrator ID','HorizontalAlignment','left');
uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.1,1/3-0.1,0.4,1/3],'style', 'text', 'String','Demonstrator Weight','HorizontalAlignment','left');

uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style', 'text', 'String','Rig Identifier','HorizontalAlignment','left');
uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.1,1/3-0.1,0.4,1/3],'style', 'text', 'String','Researcher','HorizontalAlignment','left');

uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style', 'text', 'String','Labcams address','HorizontalAlignment','left');
uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.1,1/3-0.1,0.4,1/3],'style', 'text', 'String','Labcams config file','HorizontalAlignment','left');

uicontrol('Parent', Ephys,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style','text','String','SpikeGLX host','HorizontalAlignment','left');

ha.demonID = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit','String', selectedSubjName);
ha.demonWeight = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit');

%Now still the experimenter and Rig infos
ha.rigNo = uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit');
ha.researcher = uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit');

ha.labcamsAddress = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit','String',BpodSystem.ProtocolSettings.labcamsAddress);
%On the behavior computers labcams lives in ~/labcams, with default.json.
%Another file can be selected by a button press later.
labcamsDir = fullfile(getenv('HOME'), 'labcams');
configName = 'default.json';
if isfield(BpodSystem.ProtocolSettings,'labcamsConfig') && ~isempty(BpodSystem.ProtocolSettings.labcamsConfig)
    [labcamsDir,configName,ext] = fileparts(BpodSystem.ProtocolSettings.labcamsConfig);
    configName = [configName ext];
end
if isfolder(labcamsDir)
    ha.labcamsConfigDir = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0,0,0,0],'style', 'edit','String',labcamsDir);
    %Store the directory info in a hidden uicontrol, this is to not need to
    %diplay the entire path along with the config file name, which would be
    %annoying...
    ha.labcamsConfigName = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit','String',configName);
else
     ha.labcamsConfigDir = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0,0,0,0],'style', 'edit','String','');
     ha.labcamsConfigName = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit','String','');
end

ha.spikeGLXHost = uicontrol('Parent', Ephys,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit','String',BpodSystem.ProtocolSettings.spikeGLXHost);

%Set up the ui for the button to let the user change the labcams
%config file.
sb = uicontrol('Parent', Labcams, 'Units', 'normal', 'Position', [0.55,0,0.4,1/3],'Style','pushbutton','String','Select config file',...
    'Callback',{@selectConfigButton,ha});

%Generate the button and link to the callback
pb = uicontrol('Parent', initPanel, 'Units', 'normal', 'Position', [2/3+0.1, 0.08, 1/3-0.2, 0.1],'Style','pushbutton','String','Initialize',...
    'Callback',{@initializeButton,ha,initPanel});

%Retrieve inputs and move on
set(initPanel,'Visible','on');
% The callback may finish during GUI construction, before this wait starts.
try
    drawnow;
    waitfor(initPanel, 'UserData', true)
catch ME
    if isgraphics(initPanel)
        rethrow(ME)
    end
    BpodSystem.Status.BeingUsed = 0;
    error('chipmunk_solo:InitializationCancelled', 'Session initialization was cancelled.');
end
if ~isgraphics(initPanel)
    BpodSystem.Status.BeingUsed = 0;
    error('chipmunk_solo:InitializationCancelled', 'Session initialization was cancelled.');
end
userInput = getappdata(initPanel,'Inputs');
close(initPanel)

%Add the user inputs to the experimental settings already loaded
BpodSystem.ProtocolSettings.demonID = userInput.demonID;
BpodSystem.ProtocolSettings.demonWeight = userInput.demonWeight;
BpodSystem.ProtocolSettings.rigNo = userInput.rigNo;
BpodSystem.ProtocolSettings.researcher = userInput.researcher;
BpodSystem.ProtocolSettings.labcamsAddress = userInput.labcamsAddress;
BpodSystem.ProtocolSettings.labcamsConfig = fullfile(userInput.labcamsConfigDir, userInput.labcamsConfigName);
BpodSystem.ProtocolSettings.spikeGLXHost = strtrim(userInput.spikeGLXHost);
% Session files follow labdata path_rules: {subject}/{session}/chipmunk
sessionSpecifier = char(datetime('now', 'Format',['uuuuMMdd','_','HHmmss']));
dataRoot = chipmunkDataRoot();
sessionFolder = fullfile(dataRoot, userInput.demonID, sessionSpecifier, 'chipmunk');
if ~isfolder(sessionFolder)
    mkdir(sessionFolder);
end
BpodSystem.Path.CurrentDataFile = {fullfile(sessionFolder, ...
    [userInput.demonID '_' sessionSpecifier '_chipmunk_' experimentName '.mat'])};


S = BpodSystem.ProtocolSettings; %update parameters
%% Initialize button callback function
    function initializeButton(src,event,inputHandles,figHandles)
        values = struct();
        fNames = fieldnames(inputHandles); %recover the fields
        for k=1:length(fNames)
            values.(fNames{k}) = get(inputHandles.(fNames{k}), 'String'); %copy field values to newly created fields in figure handle
        end
        values.demonID = validateChipmunkSubject(values.demonID);
        setappdata(figHandles,'Inputs',values);
        figHandles.UserData = true;
    end

function selectConfigButton(src,event,inputHandles)
    [fileName, pathName] = uigetfile('*.json', 'Select the labcams config file.');
    if isequal(fileName, 0)
        return
    end
    inputHandles.labcamsConfigDir.String = pathName; %Store the directory and file name 
    inputHandles.labcamsConfigName.String = fileName;
    end
end


function deleteIfValid(fig)
if isgraphics(fig)
    delete(fig);
end
end
