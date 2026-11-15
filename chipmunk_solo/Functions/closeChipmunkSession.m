function closeChipmunkSession(ephysOn,udplabcams)
% Save the session, then stop the camera, sound and ephys, then offer the upload.
global BpodSystem
% Keep ephys acquiring through behavioral saving and camera/sound cleanup.
streamCleanup=onCleanup(@() finishStreams(ephysOn,udplabcams));
mergeSettingsNotes();
SessionData = BpodSystem.Data;
passiveFolder = '';
if ~isempty(BpodSystem.Path.CurrentDataFile)
    save(BpodSystem.Path.CurrentDataFile{1},'SessionData')
    % The task file keeps PassiveReplay because it owns the Bpod clock and every sync pulse.
    % The copy in chipmunk_passive/ is the separate passive-stimulation dataset.
    if isfield(BpodSystem.Data,'PassiveReplay') && BpodSystem.Data.PassiveReplay.nCompleted > 0
        PassiveReplay = BpodSystem.Data.PassiveReplay;
        [taskFolder,taskName] = fileparts(BpodSystem.Path.CurrentDataFile{1});
        passiveFolder = fullfile(fileparts(taskFolder),'chipmunk_passive');
        [~,~] = mkdir(passiveFolder);
        save(fullfile(passiveFolder,[taskName '.mat']),'PassiveReplay');
    end
    trializedNoteIdx = [];
    for noteIdx = 1:length(BpodSystem.Data.Notes)
        if ~isempty(BpodSystem.Data.Notes{noteIdx})
            trializedNoteIdx(end+1) = noteIdx;
        end
    end
    if ~isempty(trializedNoteIdx)
        notesFile = fopen(fullfile(fileparts(BpodSystem.Path.CurrentDataFile{1}), 'notes.txt'), 'w');
        for noteIdx = 1:length(trializedNoteIdx)
            fprintf(notesFile, 'Trial %d: %s\n', trializedNoteIdx(noteIdx), ...
                BpodSystem.Data.Notes{trializedNoteIdx(noteIdx)});
        end
        fclose(notesFile);
    end
end
clear streamCleanup % Stop all streams before offering upload.
if ~strcmpi(BpodSystem.ProtocolSettings.demonID,'FakeSubject')
    fPath = fileparts(BpodSystem.Path.CurrentDataFile{1});
    upload = ['labdata put ' fPath ' --ask'];
    if ~isempty(passiveFolder)
        upload = [upload '; labdata put ' passiveFolder ' --ask']; % put takes one folder.
    end
    system(['export LD_LIBRARY_PATH=""; gnome-terminal -- bash -c "' upload '"']);
end
if isfield(BpodSystem.GUIHandles,'DemonStartButton') && isgraphics(BpodSystem.GUIHandles.DemonStartButton)
    set(BpodSystem.GUIHandles.DemonStartButton,'String','Finished','Enable','off');
end
end

function finishStreams(ephysEnabled,camera)
ephysCleanup=onCleanup(@() finishEphys(ephysEnabled));
if ephysEnabled
    [cameraOK,cameraError]=labcams_ephys('stop');
    if ~cameraOK,warning('chipmunk_solo:CameraStop','%s',cameraError);end
end
try
    if ~isempty(camera)
        labcamsCommand(camera,'log=end');
        labcamsCommand(camera,'softtrigger=0');
        labcamsCommand(camera,'manualsave=0');
        pause(1)
        labcamsCommand(camera,'quit=1',false);
        delete(camera);
        camera = [];
    end
catch
    warning('Could not close labcams cleanly; saving behavioral data.');
end
PsychToolboxSoundServer('Close');
end

function finishEphys(ephysEnabled)
global BpodSystem
if ~ephysEnabled,return;end
SpikeGLXControl('shutdown');
recordingState=spikeglx_client('shutdown');
BpodSystem.Data.EphysActionLog=recordingState.actionLog;
BpodSystem.Data.EphysShutdownError=recordingState.lastError;
if ~isempty(recordingState.lastError)
    warning('chipmunk_solo:EphysShutdown','%s',recordingState.lastError);
end
% Persist shutdown diagnostics after the behavioral checkpoint is already safe.
if ~isempty(BpodSystem.Path.CurrentDataFile)
    try
        SessionData=BpodSystem.Data;
        save(BpodSystem.Path.CurrentDataFile{1},'SessionData');
    catch ME
        warning('chipmunk_solo:ShutdownSave','Could not save ephys shutdown diagnostics: %s',ME.message);
    end
end
end
