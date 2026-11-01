function S = initChipmunk;
%Funtion to initialize the chipmunk protocol with different experiments and
%experimental subjects. This function requires the user to launch Bpod
%using the play button and select the chipmunk protocol along with a
%subject and the settings for the desired experiment. The selected subject
%will be considered the main one, and will thus be assigned to be the
%demonstrator in the absence of an observer and as the observer otherwise.
%The first part sets Bpod related parameters, the second part deals with
%the subject and experiment, and the third part checks the settings.
%
%Revision notes (1/14/2022): The function now includes a box for the
%miniscope identifier and it lets the user load different labcams config
%files instead of specifying cameras to record from.
%
%INPUTS: none
%OUTPUT: -S: Struct containing the experimental settings. This variable is
%            in sync with BpodSystems.ProtocolSettings most of the time
%
% LO, 4/19/2021, LO 1/14/2022
%--------------------------------------------------------------------------

%% Start setting Bpod-related options
global BpodSystem

%-----------------------------------------------------------------
%% Gather additional user input and generate file structure
%Extract the info about the experiment from the settings name (that has
%magically been copied into the subjects folder structure).
settingsPathPieces = split(BpodSystem.Path.Settings, filesep);
experimentName = settingsPathPieces{end}(1:end-4); %get the name to identify the settings. Probaly this is the most stable feature...
selectedSubjName = settingsPathPieces{end-3}; %Retrieve the name of the mouse, this is possible because the settings file is copied over to the animal's folder

%Launch an additional GUI to incorporate more info
initPanel = figure('Units','Normal','Position',[0.4, 0.2, 0.3, 0.5],'Name',experimentName,...
    'NumberTitle','off','MenuBar','none');
ha = struct(); %define empty struct for ui handles
userInput = struct();

%Generating the different UI panels to group the user inputs
Demon = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.75, 2/3, 0.25],'Title','Demonstrator','FontWeight','bold');
Setup = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.5, 2/3, 0.25],'Title','Setup','FontWeight','bold');
Labcams = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.25, 2/3, 0.25],'Title','Labcams','FontWeight','bold');
Miniscope = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0, 2/3, 0.25],'Title','Miniscope','FontWeight','bold');

%Pasting the descriptions to the user input fields
uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style', 'text', 'String','Demonstrator ID','HorizontalAlignment','left');
uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.1,1/3-0.1,0.4,1/3],'style', 'text', 'String','Demonstrator Weight','HorizontalAlignment','left');

uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style', 'text', 'String','Rig Identifier','HorizontalAlignment','left');
uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.1,1/3-0.1,0.4,1/3],'style', 'text', 'String','Researcher','HorizontalAlignment','left');

uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style', 'text', 'String','Labcams address','HorizontalAlignment','left');
uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.1,1/3-0.1,0.4,1/3],'style', 'text', 'String','Labcams config file','HorizontalAlignment','left');

uicontrol('Parent', Miniscope,'Units', 'normal', 'Position',[0.1,2/3-0.1,0.4,1/3],'style','text','String','Miniscope ID','HorizontalAlignment','left');
uicontrol('Parent', Miniscope,'Units', 'normal', 'Position',[0.1,1/3-0.1,0.4,1/3],'style','text','String','Miniscope computer address','HorizontalAlignment','left');

ha.demonID = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit','String', selectedSubjName);
ha.demonWeight = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit');

%Now still the experimenter and Rig infos
ha.rigNo = uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit');
ha.researcher = uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit');

ha.labcamsAddress = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit','String',BpodSystem.ProtocolSettings.labcamsAddress);
%On the behavior computers labcams lives in ~/labcams, with default.json.
%Another file can be selected by a button press later.
labcamsDir = fullfile(getenv('HOME'), 'labcams');
if isfolder(labcamsDir)
    ha.labcamsConfigDir = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0,0,0,0],'style', 'edit','String',labcamsDir);
    %Store the directory info in a hidden uicontrol, this is to not need to
    %diplay the entire path along with the config file name, which would be
    %annoying...
    ha.labcamsConfigName = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit','String','default.json');
else
     ha.labcamsConfigDir = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0,0,0,0],'style', 'edit','String','');
     ha.labcamsConfigName = uicontrol('Parent', Labcams,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit','String','');
end

ha.miniscopeID = uicontrol('Parent', Miniscope,'Units', 'normal', 'Position',[0.55,2/3,0.4,1/3],'style', 'edit','String',BpodSystem.ProtocolSettings.miniscopeID);
ha.miniscopeAddress = uicontrol('Parent', Miniscope,'Units', 'normal', 'Position',[0.55,1/3,0.4,1/3],'style', 'edit','String',BpodSystem.ProtocolSettings.miniscopeAddress);

%Set up the ui for the button to let the user change the labcams
%config file.
sb = uicontrol('Parent', Labcams, 'Units', 'normal', 'Position', [0.55,0,0.4,1/3],'Style','pushbutton','String','Select config file',...
    'Callback',{@selectConfigButton,ha});


%Generate the button and link to the callback
pb = uicontrol('Parent', initPanel, 'Units', 'normal', 'Position', [2/3+0.1, 0.08, 1/3-0.2, 0.1],'Style','pushbutton','String','Initialize',...
    'Callback',{@initializeButton,ha,initPanel});

%Retrieve inputs and move on
waitfor(initPanel, 'UserData') %Wait untill the initialization callback has been evaluated to continue execution
userInput = initPanel.UserData; %Store inputs
close(initPanel)

%Add the user inputs to the experimental settings already loaded
BpodSystem.ProtocolSettings.demonID = userInput.demonID;
BpodSystem.ProtocolSettings.demonWeight = userInput.demonWeight;
BpodSystem.ProtocolSettings.rigNo = userInput.rigNo;
BpodSystem.ProtocolSettings.researcher = userInput.researcher;
BpodSystem.ProtocolSettings.labcamsAddress = userInput.labcamsAddress;
BpodSystem.ProtocolSettings.labcamsConfig = fullfile(userInput.labcamsConfigDir, userInput.labcamsConfigName);
BpodSystem.ProtocolSettings.miniscopeID = userInput.miniscopeID;
BpodSystem.ProtocolSettings.miniscopeAddress = userInput.miniscopeAddress;
%--------------------------------------------------------------------------
%Find the subjects in the data directory and generate folder structure for
%storing data
%Generate the session name
sessionSpecifier = char(datetime('now', 'Format',['uuuuMMdd','_','HHmmss'])); %get date and time

%Find the Demonstrator in the data folder structure or create its folders
%and data file
BpodSystem.Path.CurrentDataFile = []; %Make sure to overrite any remainder from other sessions to be able to store values in a cell array
if ~any(strcmp(userInput.demonID, {'Virtual', 'Dummy'})) %Skip folder creation for a virtual or dummy subject. FakeSubject still gets a folder.
    if ~isfolder(fullfile(BpodSystem.Path.DataFolder,userInput.demonID)) %check whether the demonstrator exists
        mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.demonID));
    end
    mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.demonID,sessionSpecifier)); %Create a folder for the session
    mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.demonID,sessionSpecifier,'chipmunk')); %create a folder the chipmunk task info
    
    BpodSystem.Path.CurrentDataFile{1} = fullfile(BpodSystem.Path.DataFolder,userInput.demonID,sessionSpecifier,'chipmunk',...
        [userInput.demonID '_' sessionSpecifier '_chipmunk_' experimentName '.mat']);
    
end

S = BpodSystem.ProtocolSettings; %update parameters

%-------------------------------------------------------------------------
%% Initialize button callback function
    function initializeButton(src,event,inputHandles,figHandles)
        fNames = fieldnames(inputHandles); %recover the fields
        for k=1:length(fNames)
            eval(['figHandles.UserData.' fNames{k} '= get(inputHandles.' fNames{k} ',''string'');']); %copy field values to newly created fields in figure handle
        end
    end

function selectConfigButton(src,event,inputHandles)
    [fileName, pathName] = uigetfile('*.json', 'Select the labcams config file.');
    inputHandles.labcamsConfigDir.String = pathName; %Store the directory and file name 
    inputHandles.labcamsConfigName.String = fileName;
    end
end


