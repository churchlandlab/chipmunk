from labdata.schema import *

username = prefs['database']['database.user']
chipmunkschema = f'user_{username}_chipmunk'  # allows user defined schemas
if 'chipmunk_schema' in prefs.keys(): # to be able to override to another name
    chipmunkschema = prefs['chipmunk_schema']
if 'root' in chipmunkschema:
    raise(ValueError('[chipmunk] "chipmunk_schema" must be specified in the preference file to run as root.'))

chipmunkschema = dj.schema(chipmunkschema)

@chipmunkschema
class Chipmunk(dj.Imported):
    definition = """
    -> Dataset
    ---
    duration                     : float       # (seconds)
    setting_modalities           : enum('visual','audio','visual+audio')
    setting_left_reward_volume   : float
    setting_right_reward_volume  : float
    setting_prob_audio           : float
    setting_prob_vision          : float
    setting_high_rate_side       : enum('left','right')
    setting_strict_choice        : tinyint  # 1: no do overs 0: allow changing choice # ReviseChoiceFlag
    setting_free_initiation      : tinyint  # 1: animal can initiate 0: initiation time limit # PacedFlag
    setting_task_mode            : enum('detection','discrimination')

    """

    class TrialParameters(dj.Part):
        definition = """
        -> master
        trial_num                    : int
        ---
        rewarded_modality            : enum('visual','audio','visual+audio')
        stim_rate_audio = NULL       : float      # audio stimulus rate [Hz]
        stim_rate_vision = NULL      : float      # visual stimulus rate [Hz]
        category_boundary            : float 
        rewarded_position            : enum('left','right')
        stim_events = NULL           : longblob   # time of the events
        """

    class Trial(dj.Part):
        definition = """
        # Behavior table for each trial
        -> master.TrialParameters
        ---
        t_start                      : float      # trial start [seconds] WaitForCenterFixation
        t_sync    = NULL             : float      # sync pulse [seconds] Sync
        t_initiate = NULL            : float      # (initiation)[seconds] [Demon]InitFixation
        t_earlywithdraw = NULL       : float      # [Demon]EarlyWithdrawal
        t_stim = NULL                : float      # stim onset [seconds] PlayStimulus
        t_poststim = NULL            : float      # 1s if not extraStimulusTime 
        t_gocue = NULL               : float      # enter DemonWaitForWithdrawalFromCenter
        t_react = NULL               : float      # enter DemonWaitForResponse
        t_response = NULL            : float      # DemonWrongChoice or DemonReward
        t_end                        : float      # FinishTrial [seconds]
        stim_duration                : float      # default 1second + extrastim duration
        
        left_poke = NULL             : longblob   # left poke timestamps and states
        center_poke = NULL           : longblob   # center poke timestamps and states
        right_poke = NULL            : longblob   # right poke timestamps and states
        rewarded                     : tinyint
        punished                     : tinyint    # if [Demon]WrongChoice
        initiated                    : tinyint    # if [Demon]InitFixation
        early_withdrawal             : tinyint    # if [Demon]EarlyWithdrawal
        with_choice                  : tinyint    # if [Demon]WrongChoice or [Demon]Reward
        response = 0                 : tinyint    # -1:left, 0:no response, 1:right
        """
    
    def make(self,key):
        localpath = prefs['local_paths'][0]
        if key['dataset_name'] == 'chipmunk':
            filekey = (Dataset.DataFiles() & key & 'file_path LIKE "%.mat"').fetch(as_dict= True)
            if not len(filekey):
                RuntimeWarning(f'[chipmunk]: Dataset does not contain the log file {key}')
                return
            filename = None
            local = None
            file_keys = File() & (Dataset.DataFiles() & key)
            filenames = file_keys.get() # downloads if not there.
            assert not len(filenames) is None, ValueError(f'Dataset {key} is not in {prefs["local_paths"]}')
            from .utils import process_chipmunk_file
            (trialdicts,
             trial_parametersdicts,
             settingsdict), metadata = process_chipmunk_file((File() & filekey).get()[0])
            computer_name = None
            if not metadata['setup_name'] is None:
                # add if not there
                computer_name = metadata['setup_name']
                if not computer_name in Setup().fetch('setup_name'):
                    locations = SetupLocation().fetch(as_dict = True)
                    if len(locations):
                        Setup.insert1(dict(locations[0],setup_name = computer_name,setup_description = 'Added automatically.'))
                    else:
                        computer_name = None
                        
            if not metadata['experimenter'] is None:
                # retrieve the name
                namesdict = LabMember().fetch(as_dict=True)
                namesdict = [dict(u,name = ' '.join([u['first_name'],u['last_name']])) for u in namesdict]
                experimenter = [u for u in namesdict if metadata['experimenter'] in u['name']]
                if not len(experimenter):
                    raise(ValueError(f'[chipmunk] LabMember {metadata["experimenter"]} not in database?'))
                user_name = experimenter[0]['user_name']
                # update the session.
                ses = (Session() & (Dataset & key)).fetch1()
                ses['experimenter'] = user_name
                Session.update1(ses)
                
            dset = (Dataset & key).fetch1()
            notes = metadata['notes'] if not metadata['notes'] == '' else None
            if not notes is None:
                ses = (Session() & (Dataset & key)).fetch1()
                
                if dset['note_datetime'] is None:
                    note = dict(note_datetime = ses['session_datetime'],
                                notetaker = user_name,
                                notes = notes)
                    if note['notetaker'] is None:
                        note['notetaker'] = ses['experimenter']
                    Note.insert1(note)
                    dset['notetaker'] = note['notetaker']
                    dset['note_datetime'] = note['note_datetime']
                    Dataset.update1(dset)
            # update the setup_name
            if not computer_name is None:
                dset['setup_name'] = computer_name
                Dataset.update1(dset)
                
            if not len(trialdicts):
                print(f'[chipmunk]: There are no trials for {key}')
                return
            
            self.insert1(dict(key,**settingsdict))
            self.TrialParameters.insert([dict(key,**d) for d in trial_parametersdicts])
            self.Trial.insert([dict(key,**d) for d in trialdicts])
            # get example frames for each camera
            # align the video to the behavior data
            from .utils import extract_chipmunk_camera_data
            cameras, frames, camera_events = extract_chipmunk_camera_data(file_keys.get(),trialdicts)
            riglogevents = []
            if len(camera_events):
                riglogevents.extend(camera_events)
                
            stream = dict(key,stream_name = 'bpod')
            digital = dict(stream,
                           event_name = 'sync',
                           event_timestamps = [t['t_sync'] for t in trialdicts], 
                           event_values = [t['trial_num'] for t in trialdicts])
            
            DatasetEvents.insert1(stream,
                                  skip_duplicates = True,
                                  allow_direct_insert = True)
            DatasetEvents.Digital.insert1(digital,
                                          skip_duplicates = True,
                                          allow_direct_insert = True)

            for c in cameras:
                c['file_path'] = str(c['file_path']).replace(localpath,'').strip(pathlib.os.sep)
                storage = (File() & dict(file_path = c['file_path'])).fetch('storage')
                assert len(storage), ValueError(f'File {c["file_path"]} is not backed up - cannot add.')
                c['storage'] = storage[0]

            DatasetVideo.insert([dict(key,**c) for c in cameras],
                                skip_duplicates = True,
                                ignore_extra_fields = True)
            DatasetVideo.File.insert([dict(key,**c) for c in cameras],
                                     skip_duplicates = True,
                                     ignore_extra_fields = True)
            DatasetVideo.Frame.insert([dict(key,**f) for f in frames],
                                      skip_duplicates = True,
                                      ignore_extra_fields = True)
            # should also run chipmunk_insert_decision_task but has to be changed to allow.
            from .utils import chipmunk_insert_decision_task
            chipmunk_insert_decision_task(key)
