
function [S, errorCode] = initChipmunk;
%Funtion to initialize the chipmunk protocol with different experiments and
%experimental subjects. This function requires the user to launch Bpod
%using the play button and select the chipmunk protocol along with a
%subject and the settings for the desired experiment. The selected subject
%will be considered the main one, and will thus be assigned to be the
%demonstrator in the absence of an observer and as the observer otherwise.
%The first part sets Bpod related parameters, the second part deals with
%info about the subject and experiment and the third part checks the
%settings for the experiment.
%
%INPUTS: none
%OUTPUTS: -S: Struct containing the experimental settings
%         -errorCode: Errors during the
%                         execution of chipmunk. Reports incompatibilities
%                         and will return an error code for them.


%% Start setting Bpod-related options
global BpodSystem
%add the path to the external functions first
addpath(fullfile(BpodSystem.Path.ProtocolFolder,'chipmunk','Functions'));

%Find sound card for stimuli
PsychToolboxSoundServer('init'); % Try and let this crash before all the other inputs are passed

%Set soft code handler to trigger sounds
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';
%-----------------------------------------------------------------
%% Gather additional user input and generate file structure
%extract the info about the experiment from the settings name (that has
%magically been copied into the subjects folder structure).
settingsPathPieces = split(BpodSystem.Path.Settings, filesep);
experimentName = settingsPathPieces{end}(1:end-4); %get the name to identify the settings. Probaly this is the most stable feature...

%Get the name of the subject that has been selected
currentDataPathPieces = split(BpodSystem.Path.CurrentDataFile,filesep);
selectedSubjName = currentDataPathPieces{end-3}; %%Bpod hierarchy from bottom up is: data file, Session Data Folder, Task, Subject

%Launch an additional GUI to incorporate more info
initPanel = figure('Units','Normal','Position',[0.4, 0.2, 0.3, 0.5],'Name',experimentName,...
    'NumberTitle','off','MenuBar','none');
ha = struct(); %define empty struct for ui handles
userInput = struct();

%Generating the different UI panels to group the user inputs
Demon = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.75, 2/3, 0.25],'Title','Demonstarator');
Obs = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.5, 2/3, 0.25],'Title','Observer');
Setup = uipanel('Parent', initPanel, 'Units', 'normal', 'Position', [0, 0.25, 2/3, 0.25],'Title','Setup');

%Pasting the descriptions to the user input fields
uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0,1/3-0.1,0.7,1/3],'style', 'text', 'String','Demonstrator ID');
uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0,0-0.1,0.7,1/3],'style', 'text', 'String','Demonstrator Weight');

uicontrol('Parent', Obs,'Units', 'normal', 'Position',[0,1/3-0.1,0.7,1/3],'style', 'text', 'String','Observer ID');
uicontrol('Parent', Obs,'Units', 'normal', 'Position',[0,0-0.1,0.7,1/3],'style', 'text', 'String','Observer Weight');

uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0,1/3-0.1,0.7,1/3],'style', 'text', 'String','Rig Identifier');
uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0,0-0.1,0.7,1/3],'style', 'text', 'String','Researcher');

%Generating the edit fileds for user input
%Check all conditions that feature a real demonstrator or performer and
%prefill with the selected subjectName
if ~strcmpi(experimentName,'ObserverFixation') && ~strcmpi(experimentName,'ObserverTask')
    ha.demonID = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.7,1/3,0.3,1/3],'style', 'edit', 'String',selectedSubjName);
    ha.demonWeight = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.7,0,0.3,1/3],'style', 'edit');
elseif strcmp(experimentName,'ObserverFixation') %virtual task runs, no demonstrator
    uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.7,1/3-0.1,0.3,1/3],'style', 'text', 'String','Virtual');
    ha.demonID = 'Virtual';
    ha.obsID = uicontrol('Parent', Obs,'Units', 'normal', 'Position',[0.7,1/3,0.3,1/3],'style', 'edit', 'String', selectedSubjName);
    ha.obsWeight = uicontrol('Parent', Obs,'Units', 'normal', 'Position',[0.7,0,0.3,1/3],'style', 'edit');
elseif strcmp(experimentName,'ObserverTask') %Here the observer is the main subject
    ha.demonID = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.7,1/3,0.3,1/3],'style', 'edit','String','Dummy'); %pre-fill with meaningless value for folder
    ha.demonWeight = uicontrol('Parent', Demon,'Units', 'normal', 'Position',[0.7,0,0.3,1/3],'style', 'edit');
    ha.obsID = uicontrol('Parent', Obs,'Units', 'normal', 'Position',[0.7,1/3,0.3,1/3],'style', 'edit', 'String', selectedSubjName);
    ha.obsWeight = uicontrol('Parent', Obs,'Units', 'normal', 'Position',[0.7,0,0.3,1/3],'style', 'edit');
end

%Now still the experimenter and Rig infos
ha.rigNo = uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.7,1/3,0.3,1/3],'style', 'edit');
ha.researcher = uicontrol('Parent', Setup,'Units', 'normal', 'Position',[0.7,0,0.3,1/3],'style', 'edit');

%Generate the button and link to the callback
pb = uicontrol('Parent', initPanel, 'Units', 'normal', 'Position', [2/3+0.1, 0.08, 1/3-0.2, 0.1],'Style','pushbutton','String','Initialize',...
    'Callback',{@initializeButton,ha,initPanel});

%Retrieve inputs and move on
waitfor(initPanel, 'UserData') %Wait untill the initialization callback has been evaluated to continue execution
userInput = initPanel.UserData; %Store inputs
close(initPanel)

%Find the subjects in the data directory and generate folder structure for
%storing data
%Generate the session name
sessionSpecifier = char(datetime('now', 'Format',['uuuuMMdd','_','HHmmss'])); %get date and time

%Find the Demonstrator in the data folder structure or create its folders
if ~strcmp(userInput.demonID,'Virtual') || ~strcmp(userInput,'Dummy') %For the main subject FakeSubject is chosen, while for the other one Dummy will be the assigned name, no folder is created for Dummy
    if ~isfolder(fullfile(BpodSystem.Path.DataFolder,userInput.demonID)) %check whether the demonstrator exists
        mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.demonID));
    end
    if ~isfolder(fullfile(BpodSystem.Path.DataFolder,userInput.demonID,'chipmunk')) %check whether it contains the chipmunk task
        mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.demonID,'chipmunk'));
    end
    mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.demonID,'chipmunk', sessionSpecifier)); %create a folder with the respective session date and time
    mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.demonID,'chipmunk', sessionSpecifier,experimentName)); %create folder with the experiment name
end

%Also find or create a folder for the observer if required and generate the
%final data name
if isfield(userInput,'ObserverID')
    if ~isfolder(fullfile(BpodSystem.Path.DataFolder,userInput.obsID)) %check whether the observer exists
        mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.obsID));
    end
    if ~isfolder(fullfile(BpodSystem.Path.DataFolder,userInput.obsID,'chipmunk')) %check whether it contains the chipmunk task
        mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.obsID,'chipmunk'));
    end
    mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.obsID,'chipmunk', sessionSpecifier)); %create a folder with the respective session date and time
    mkdir(fullfile(BpodSystem.Path.DataFolder,userInput.obsID,'chipmunk', sessionSpecifier,experimentName)); %create folder with the experiment name
    
    %Define the name of the file to be saved. If there is an observer include
    %both subject's names separated by _x_, only put performer otherwise
    dataFile = fullfile(BpodSystem.Path.DataFolder,userInput.obsID,'chipmunk', sessionSpecifier,experimentName,...
        [userInput.demonID '_x_' userInput.obsID '_' experimentName '_' sessionSpecifier '_chipmunk.mat']);
else
    dataFile = fullfile(BpodSystem.Path.DataFolder,userInput.obsID,'chipmunk', sessionSpecifier,experimentName,...
        [userInput.demonID '_' experimentName '_' sessionSpecifier '_chipmunk.mat']);
end

BpodSystem.Path.CurrentDataFile = dataFile; %use our dataFile name
%--------------------------------------------------------------------------
%% Load and check the settings for this experiment
%Load experiment settings and check whether name and original settings are
%consistent
%Preallocate the outputs
S = []; errorCode = 0;
originalExperimentName = BpodSystem.ProtocolSettings.experimentName; %compare the experiment name stored inside the structure with the one of the file
if ~strcmpi(experimentName, originalExperimentName) %Does the name match the original experiment name in the settings?
    display(sprintf('The experimental settings file name is not consistent with the original file name.\nChipmunk will end.'))
    errorCode = 1;
end

%Add the user inputs to the experimental settings already loaded
BpodSystem.ProtocolSettings.demonID = userInput.demonID;
BpodSystem.ProtocolSettings.demonWeight = userInput.demonWeight;
if isfield(userInput,'obsID')
    BpodSystem.ProtocolSettings.obsID = userInput.obsID;
    BpodSystem.ProtocolSettings.obsWeight = userInput.obsWeight;
end
BpodSystem.ProtocolSettings.rigNo = userInput.rigNo;
BpodSystem.ProtocolSettings.researcher = userInput.researcher;

%Compare the user-selected settings to the standard settings stored under
%Experiments in chimunk
load(fullfile(BpodSystem.Path.ProtocolFolder,'chipmunk','Experiments',[experimentName '.mat']),'standardSettings') %load the standard settings saved as standardSettings
standardFieldNames = fieldnames(standardSettings);
standardFieldVals = struct2cell(standardSettings);
userSetFieldNames = fieldnames(BpodSystem.ProtocolSettings); %unfortunately still named after the protocol and not the experiment...

%spot every field in the standard settings to make sure you include it
for n=1:length(standardFieldNames)
    foundField = false;
    for j=1:length(userSetFieldNames)
        if strcmpi(standardFieldNames{n},userSetFieldNames{j});
            foundField = true;
        end
    end
    if ~foundField
        BpodSystem.ProtocolSettings.standardFieldNames{n} = standardFieldVals{n};
    end
end

S = BpodSystem.ProtocolSettings; %update parameters

%--------------------------------------------------------
%% Junk to be deleted when tested.....
%Assigning values to Bpod object (paths, status etc.)
% BpodSystem.Status.Live = 1; %Switch internal status on
% BpodSystem.Status.BeingUsed = 1; %
% BpodSystem.Path.CurrentDataFile = dataFile; %use our dataFile name
% BpodSystem.Data = struct('Demonstrator',[], 'Observer',[]);
% BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';
% BpodSystem.ProtocolSettings = struct();
% BpodSystem.ProtocolStartTime = now;
% %--------
% %Now the settings...
% [settingsFile, settingsPath] = uigetfile(fullfile(BpodSystem.Path.DataFolder,userInput.Performer_DemonstratorID,'chipmunk'),...
%     'Select a settings file for the current experiment or leave empty to choose the standard settings')
%
% %BpodSystem.Path.CurrentSettings =;
% PsychToolboxSoundServer('init');
% set(BpodSystem.GUIHandles.RunButton,'cdata', BpodSystem.GUIHandles.PauseButton, 'TooltipString', 'Press to pause session') %switch the run button from play to pause
%
%
%
% %-----
% %Open an editor to allow the user to document incidents
% fileContents{1} = ['cd "C:\Users\Public\"'];
% fileContents{2} = ['echo.>' path 'SessionNotes.txt'];
% fileContents{3} = ['notepad.exe' path 'SessionNotes.txt'];
%
% fid = fopen('C:\Users\Lukas Oesch\linkerFile.cmd','w'); %write the file to a place that exists on every Win
% fprintf(fid,'%s \n', fileContents{:});
% fclose(fid);
% %------------
% cdOld = cd;
% cd(path) %starts the command prompt from the Matlab path
% system(['echo.>SessionNotes.txt']) %processes the string as a command
% system(['notepad.exe SessionNotes.txt'])
%
%
% %
% allFolders = split(BpodSystem.Path.CurrentDataFile,filesep);
% subjectFolder = [];
% for k=1:length(allFolders)-3 %Bpod hierarchy from bottom up is: data file, Session Data Folder, Task, Subject
%     subjectFolder = fullfile(subjectFolder, allFolders{k});
% end
% %Construct the file path and generate the folders so that it is consistent with datajoint:
% % Subject -> Session (date and time) -> Task -> Data
% mkdir(subjectFolder, char(datetime('now', 'Format',['uuuuMMdd','_','HHmmss']))); %First create session folder
% mkdir(subjectFolder, fullfile(char(datetime('now', 'Format',['uuuuMMdd','_','HHmmss'])), allFolders{end-2}));%Second the task folder
%
% subjectFolder = fullfile(subjectFolder, char(datetime('now', 'Format',['uuuuMMdd','_','HHmmss'])), allFolders{end-2});
%
%
% BpodSystem.Path.CurrentDataFile = fullfile(subjectFolder,allFolders{end});
%
%-------------------------------------------------------------------------
%% Initialize button callback function
    function initializeButton(src,event,inputHandles,figHandles)
        fNames = fieldnames(inputHandles); %recover the fields
        for k=1:length(fNames)
            eval(['figHandles.UserData.' fNames{k} '= get(inputHandles.' fNames{k} ',''string'');']); %copy field values to newly created fields in figure handle
        end
    end
end


