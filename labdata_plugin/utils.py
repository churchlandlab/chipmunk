from labdata.utils import *
import warnings

def load_chipmunk_trialdata(file_name):
    '''Read the behavioral data from .mat or .obsmat and return a
    pandas data frame with the respective data for each trial
    Parameters
    ----------
    file_name: string, path to a chipmunk .mat or .obsmat file
    Returns
    -------
    trialdata: pandas data frame, data about the timing of states and events, choices and outcomes etc.
    Examples
    --------
    trial_data = load_chipmunk_trialdata(file_name)

    Port1 - 'left'
    Port2 - 'center'
    Port3 - 'right'
    '''
    import os
    import pandas as pd
    from scipy.io import loadmat
    import numpy as np
    metadata = None
    try:
        sesdata = loadmat(file_name, squeeze_me=True,
                              struct_as_record=True)['SessionData']
        if 'Notes' in sesdata.dtype.names:
            notes = sesdata['Notes']
            notes = '\n'.join([f'trial:{itrial};{note}' for itrial,note in enumerate(notes.tolist()) if len(note)])
        else:
            notes = ''
        tset = sesdata['TrialSettings'].tolist()
        setup_name = tset['rigNo'][0]
        experimenter = tset['researcher'][0]
        metadata = dict(notes = notes,
                        setup_name = setup_name,
                        experimenter = experimenter)
        
        tmp = sesdata['RawEvents'].tolist()
        tmp = tmp['Trial'].tolist()
        uevents = np.unique(np.hstack([t['Events'].tolist().dtype.names for t in tmp])) #Make sure not to duplicate state definitions
        ustates = np.unique(np.hstack([t['States'].tolist().dtype.names for t in tmp]))
        trialevents = []
        trialstates = [] #Extract all trial states and events
        for t in tmp:
             a = {u: np.array([np.nan]) for u in uevents}
             s = t['Events'].tolist()
             for b in s.dtype.names:
                 if isinstance(s[b].tolist(), float) or isinstance(s[b].tolist(), int):
                     #Make sure to include single values as an array with a dimension
                     #Arrgh, in the unusual case that a value is an int this should also apply!
                     a[b] = np.array([s[b].tolist()])
                 else:
                        a[b] = s[b].tolist()
             trialevents.append(a)
             a = {u:None for u in ustates}
             s = t['States'].tolist()
             for b in s.dtype.names:
                     a[b] = s[b].tolist()
             trialstates.append(a)
        trialstates = pd.DataFrame(trialstates)
        trialevents = pd.DataFrame(trialevents)
        trialdata = pd.merge(trialevents,trialstates,left_index=True, right_index=True)
        # Insert a column for DemonWrongChoice in trialda if necessary
        if 'DemonWrongChoice' not in trialdata.columns:
            trialdata.insert(trialdata.shape[1], 'DemonWrongChoice', [np.array([np.nan, np.nan])] * trialdata.shape[0])
        #Add response and stimulus train related information: correct side, rate, event occurence time stamps
        trialdata.insert(trialdata.shape[1], 'response_side', sesdata['ResponseSide'].tolist())
        trialdata.insert(trialdata.shape[1], 'correct_side', sesdata['CorrectSide'].tolist())
        #Get stim modality
        tmp_modality_numeric = sesdata['Modality'].tolist()
        temp_modality = []
        for t in tmp_modality_numeric:
            if t == 1:
                temp_modality.append('visual')
            elif t == 2:
                temp_modality.append('auditory')
            elif t == 3:
                temp_modality.append('audio+visual')
            else:
                temp_modality.append(np.nan)
                print('[chipmunk]: Could not determine modality and set value to nan')
        trialdata.insert(trialdata.shape[1], 'stimulus_modality', temp_modality)
        trialdata.insert(trialdata.shape[1], 'category_boundary', sesdata['CategoryBoundary'])
        trialdata.insert(trialdata.shape[1], 'stimulus_rate_visual', sesdata['StimulusRate'].tolist()[:,0])
        trialdata.insert(trialdata.shape[1], 'stimulus_rate_auditory', sesdata['StimulusRate'].tolist()[:,1])
        
        #Reconstruct the time stamps for the individual stimuli
        event_times = []
        event_duration = sesdata['StimulusDuration'].tolist()[0]
        for t in range(trialdata.shape[0]):
            if tmp_modality_numeric[t] < 3: #Unisensory
                temp_isi = sesdata['InterStimulusIntervalList'].tolist().tolist()[t][tmp_modality_numeric[t]-1]
                #Index into the corresponding trial and find the isi for the corresponding modality
            else:
                temp_isi = sesdata['InterStimulusIntervalList'].tolist().tolist()[t][0]
                #For now assume synchronous and only look at visual stims
                warnings.warn('[chipmunk]: Found multisensory trials, assumed synchronous condition')
            temp_trial_event_times = [temp_isi[0]]
            for k in range(1,temp_isi.shape[0]-1): #Start at 1 because the first Isi is already the timestamp after the play stimulus
                temp_trial_event_times.append(temp_trial_event_times[k-1] + event_duration + temp_isi[k])
            event_times.append(temp_trial_event_times + trialdata['PlayStimulus'][t][0]) #Add the timestamp for play stimulus to the event time
        trialdata.insert(trialdata.shape[1], 'stimulus_event_timestamps', event_times)
        #Insert the outcome record for faster access to the different trial outcomes
        trialdata.insert(0, 'outcome_record', sesdata['OutcomeRecord'].tolist())
        try:
            tmp = sesdata['TrialDelays'].tolist()
            for key in tmp[0].dtype.fields.keys(): #Find all the keys and extract the data associated with them
                tmp_delay = tmp[key].tolist()
                trialdata.insert(trialdata.shape[1], key , tmp_delay)
        except:
            print('[chipmunk]: For this version of chipmunk the task delays struct was not implemented yet.\nDid not generate the respective columns in the data frame.')
        tmp = sesdata['ActualWaitTime'].tolist()
        trialdata.insert(trialdata.shape[1], 'actual_wait_time' , tmp)
        #TEMPORARY: import the demonstrator and observer id
        tmp = sesdata['TrialSettings'].tolist()
        trialdata.insert(trialdata.shape[1], 'demonstrator_ID' , tmp['demonID'].tolist())
        #Add a generic state tracking the timing of outcome presentation, this is also a 1d array of two elements
        outcome_timing = []
        for k in range(trialdata.shape[0]):
            if np.isnan(trialdata['DemonReward'][k][0]) == 0:
                outcome_timing.append(np.array([trialdata['DemonReward'][k][0], trialdata['DemonReward'][k][0]]))
            elif np.isnan(trialdata['DemonWrongChoice'][k][0]) == 0:
                outcome_timing.append(np.array([trialdata['DemonWrongChoice'][k][0],trialdata['DemonWrongChoice'][k][0]]))
            else:
                outcome_timing.append(np.array([np.nan, np.nan]))
        trialdata.insert(trialdata.shape[1], 'outcome_presentation', outcome_timing)
        # Retrieve the flag for revised choices
        if 'ReviseChoiceFlag' in sesdata.dtype.names:
            trialdata.insert(trialdata.shape[1], 'revise_choice_flag', np.ones(trialdata.shape[0], dtype = bool) * sesdata['ReviseChoiceFlag'].tolist())
        else:
            print('There was no ReviseChoiceFlag.')
            trialdata.insert(trialdata.shape[1], 'revise_choice_flag', np.ones(trialdata.shape[0], dtype = bool) * 0)
        #Get the Bpod timestamps for the start of each new trial
        trialdata.insert(trialdata.shape[1], 'trial_start_time' , sesdata['TrialStartTimestamp'].tolist())
        #----Get the timestamp of when the mouse gets out of the response poke
        #Here, a minimum poke duration of 100 ms is a requirement. Coming out
        #of the response port after less than 100 ms is not considered a retraction
        #an will be ignored and the next Poke out event will be counted.
        #Note: The timestamps are always calculated with respect to the
        #start of the trial during which the response happened, even if the
        #mouse only retracted on the next trial (usually when rewarded!)
        #Also note that there is always a < 100 ms period where Bpod does
        #not run a state machine and thus doesn't log events. It is possible that
        #that retraction events might be missed because of this interruption.
        #These missed events will be nan.
        response_port_out = []
        for k in range(trialdata.shape[0]):
            event_name = None
            if trialdata['response_side'][k] == 0:
                event_name = 'Port1Out'
            elif trialdata['response_side'][k] == 1:
                event_name = 'Port3Out'
            poke_ev = None
            if event_name is not None:
                #First check current trial
                add_past_trial_time = 0 #Time to be added if the retrieval only happens in the following trial
                tmp = trialdata[event_name][k][trialdata[event_name][k] > trialdata['outcome_presentation'][k][0]]
                #Now sometimes the mice retract very fast, faster than the normal reaction time
                #skip these events in this case and consider the next one
                candidates = tmp.shape[0]
                looper = 0
                while (poke_ev is None) & (looper < candidates):
                    tmptmp = tmp[looper]
                    if tmptmp - trialdata['outcome_presentation'][k][0] > 0.1:
                        poke_ev = tmptmp
                    looper = looper + 1
                if poke_ev is None: #Did not find a poke out event that fullfills the criteria
                    if k < (trialdata.shape[0] - 1): # Stop from checking at the very end...
                        tmp = trialdata[event_name][k+1][trialdata[event_name][k+1] < trialdata['Port2In'][k+1][0]]
                        #Check all the candidate events at the beginning of the next trial but before center fixation.
                        add_past_trial_time = trialdata['trial_start_time'][k+1] - trialdata['trial_start_time'][k]
                        if tmp.shape[0] > 0:
                            poke_ev = np.min(tmp) #These would actually come sorted already...
            if poke_ev is not None:
                response_port_out.append(np.array([poke_ev + add_past_trial_time, poke_ev + add_past_trial_time]))
            else:
                response_port_out.append(np.array([np.nan, np.nan]))
        trialdata.insert(trialdata.shape[1], 'response_port_out', response_port_out)
        outcome_end = []
        for k in range(trialdata.shape[0]):
            if np.isnan(trialdata['DemonReward'][k][0]) == 0:
                outcome_end.append(np.array([trialdata['response_port_out'][k][0], trialdata['response_port_out'][k][0]]))
            elif np.isnan(trialdata['DemonWrongChoice'][k][0]) == 0:
                outcome_end.append(np.array([trialdata['FinishTrial'][k][0],trialdata['FinishTrial'][k][0]]))
            else:
                outcome_end.append(np.array([np.nan, np.nan]))
        trialdata.insert(trialdata.shape[1], 'outcome_end', outcome_end)
        if 'ObsOutcomeRecord' in sesdata.dtype.fields:
            trialdata.insert(1, 'observer_outcome_record', sesdata['ObsOutcomeRecord'].tolist())
            tmp = sesdata['ObsActualWaitTime'].tolist()
            trialdata.insert(trialdata.shape[1], 'observer_actual_wait_time' , tmp)
            tmp = sesdata['TrialSettings'].tolist()
            trialdata.insert(trialdata.shape[1], 'dobserver_ID' , tmp['obsID'].tolist())

    except Exception as err:
        warnings.warn(f"[chipmunk]: An error occured and {file_name} could not be loaded")
        print(err)
    return trialdata,sesdata,metadata

def _get_state_time(trial, states = [],index = 0):
    if not len(states):
        return None
    if type(states) is str:
        states = [states]
    time =  None # in case the state does not exist..
    for state  in states:
        statekeys = [k for k in trial.keys() if state in k]
        if len(statekeys):
            time = trial[statekeys[0]][index]
            if np.isfinite(time):
                break
    if not np.isfinite(time):
        return None
    return time + trial.trial_start_time
    
def _get_port(trial,port):
    port = np.vstack((np.array([np.array([p,1]) for p in trial[f'{port}In']]),np.array([np.array([p,0]) for p in trial[f'{port}Out']])))
    port = port[np.argsort(port[:,0]),:]
    port = port[np.isfinite(port[:,0]),:]
    if not len(port):
        return None
    port[:,0] += trial.trial_start_time
    return port

def process_chipmunk_file(filepath):
    trialdata,session_data,metadata = load_chipmunk_trialdata(filepath)

    # process settings from the entire session
    setting_high_rate_side = 'right' if (session_data['SettingsFile'].tolist())['highRateSide'] == 'R' else 'left'
    setting_prob_audio = session_data['SettingsFile'].tolist()['propOnlyAuditory'].tolist()
    setting_prob_vision = session_data['SettingsFile'].tolist()['propOnlyVisual'].tolist()
    if setting_prob_audio == 1:
        setting_modalities = 'audio'
    elif setting_prob_vision == 1:
        setting_modalities = 'visual'
    else:
        setting_modalities = 'visual+audio'

    setting_strict_choice = 0
    setting_free_choice = 0
    if 'ReviseChoiceFlag' in session_data.dtype.names:
        setting_strict_choice = session_data['ReviseChoiceFlag'].tolist() == 0
    if 'PacedFlag' in session_data.dtype.names:
        setting_free_choice = session_data['PacedFlag'].tolist() == 0
        
    
    setting_left_reward_volume = session_data['TrialSettings'].tolist()['leftRewardVolume'][0]
    setting_right_reward_volume = session_data['TrialSettings'].tolist()['rightRewardVolume'][0]
    
    settings_dict = dict(setting_modalities = setting_modalities,
                         setting_left_reward_volume = setting_left_reward_volume,
                         setting_right_reward_volume = setting_right_reward_volume,
                         setting_prob_vision = setting_prob_vision,
                         setting_prob_audio = setting_prob_audio,
                         setting_high_rate_side = setting_high_rate_side,
                         setting_strict_choice = setting_strict_choice,
                         setting_free_initiation = setting_free_choice)
    # process settings from each trial and the outcomes
    trials_dict = []
    trial_settings_dict = []
    for itrial, trial in trialdata.iterrows():
        trialtimes = dict(trial_num = itrial,
                          t_start = _get_state_time(trial,'WaitForCenterFixation'), 
                          t_sync = _get_state_time(trial,'Sync'),         
                          t_initiate = _get_state_time(trial,'InitFixation'),
                          t_earlywithdraw = _get_state_time(trial,'EarlyWithdrawal'), 
                          t_stim = _get_state_time(trial,'PlayStimulus'),
                          t_gocue = _get_state_time(trial,'WaitForWithdrawalFromCenter'),
                          t_react = _get_state_time(trial,'WaitForResponse'),
                          t_response = _get_state_time(trial,['Reward','WrongChoice']),
                          t_end = _get_state_time(trial,'FinishTrial'))

        stim_duration = 1. + trial['ExtraStimulusDuration']
        if not trialtimes['t_earlywithdraw'] is None:
            # trim the stim duration to the withdrawal time
            if not trialtimes['t_stim'] is None:
                stim_duration = np.min([stim_duration,trialtimes['t_earlywithdraw']-trialtimes['t_stim']])
            else:
                stim_duration = 0
        if not trialtimes['t_response'] is None:
            # trim the stim duration to the withdrawal time
            stim_duration = np.min([stim_duration,trialtimes['t_response']-trialtimes['t_stim']])
        if trialtimes['t_initiate'] is None:
            stim_duration = 0.

        response = -1 if trial.response_side == 0 else 0
        response = 1 if trial.response_side == 1 else response
        
        trials_dict.append(dict(trialtimes,
                                stim_duration = stim_duration,
                                left_poke = _get_port(trial,'Port1'),
                                center_poke = _get_port(trial,'Port2'),
                                right_poke = _get_port(trial,'Port3'),
                                initiated = 1 if not _get_state_time(trial, states = 'InitFixation') is None else 0,
                                rewarded = 1 if not _get_state_time(trial, states = 'Reward') is None else 0,
                                punished = 1 if not _get_state_time(trial, states = 'WrongChoice') is None else 0,
                                early_withdrawal = 1 if not _get_state_time(trial, states = 'EarlyWithdrawal') is None else 0,
                                with_choice = 0 if trialtimes['t_response'] is None else 1,
                                response = response))
        modality = None
        if trial.stimulus_modality == 'auditory':
            modality = 'audio'
        elif trial.stimulus_modality == 'visual':
            modality = 'visual'
        elif trial.stimulus_modality == 'multisensory':
            modality = 'visual+audio'
        else:
            raise(ValueError(f'[chipmunk]: Unknown modality {trial.stimulus_modality}'))
        
        trial_settings_dict.append(dict(trial_num = itrial,
                                        rewarded_modality = modality,
                                        stim_rate_audio = trial.stimulus_rate_auditory if np.isfinite(trial.stimulus_rate_auditory) else None,
                                        stim_rate_vision = trial.stimulus_rate_visual if np.isfinite(trial.stimulus_rate_visual) else None,
                                        category_boundary = trial.category_boundary,
                                        rewarded_position = 'right' if trial.correct_side == 1 else 'left',
                                        stim_events = [f for f in trial.stimulus_event_timestamps]))
    max_stims = np.max([len(np.unique([t['stim_rate_audio'] 
                                   for t in trial_settings_dict 
                                   if not t['stim_rate_audio'] is None])),
                    len(np.unique([t['stim_rate_vision'] 
                                   for t in trial_settings_dict 
                                   if not t['stim_rate_vision'] is None]))])
    settings_dict['setting_task_mode'] = 'detection' if max_stims <= 2 else 'discrimination'
    settings_dict['duration'] = trials_dict[-1]['t_end'] - trials_dict[0]['t_start']
    return (trials_dict, trial_settings_dict,settings_dict),metadata

def read_camlog(log):
    '''
    Adapted from github.com/jcouto/labcams 
    '''
    
    logheaderkey = '# Log header:'
    comments = []
    with open(log,'r',encoding = 'utf-8') as fd:
        for line in fd:
            if line.startswith('#'):
                line = line.strip('\n').strip('\r')
                comments.append(line)
                if line.startswith(logheaderkey):
                    columns = line.strip(logheaderkey).strip(' ').split(',')
    camlog = pd.read_csv(log, delimiter = ',',
                         header = None,
                         comment = '#',
                         engine = 'c')
    return comments,camlog

def _handle_chipmunk_camera_sync(icam, camlog, comm, vid, trialdicts):
    '''
    Handles the camera sync for the chipmunk task. 
    These frametimes may have to be interpolated when .

    Returns interpolated frametimes and events

    frametimes, events = _handle_chipmunk_camera_sync(icam, camlog, comm, vid, trialdicts)

    Joao Couto - 2025
    '''

    trialmarkers = [t['t_sync'] for t in trialdicts]
    trialmarkers_trials = [t['trial_num'] for t in trialdicts]
    if not camlog.shape[1] == 3:# then there are syncs
        raise(ValueError('The camera log has the wrong shape?')) # there is an issue, raise...
    frame_num = camlog[camlog.columns[0]].values  # time
    t = camlog[camlog.columns[1]].values  # time
    idx = np.argsort(t)
    t = t[idx]
    frame_num = frame_num[idx]
    x = camlog[camlog.columns[-1]].values[idx] 
    
    # unpack the camera bits
    xshape = list(x.shape)
    x = x.reshape([-1,1])
    to_and = 2**np.arange(16).reshape([1,16])
    gpio = (x & to_and).astype(bool).astype(int).reshape(xshape + [16])
    # check which channels change:  
    channel_selection = np.where([len(np.unique(g))>1 for g in gpio.T])[0]
    if not len(channel_selection):
        print("[Warning] GPIO was not connected? for the camera, using the network events.")
        gpio = []
    else:
        gpio = gpio[:,channel_selection].T
    # sync to the task
    frametimes = None
    for iin,g in zip(channel_selection,gpio):
        # do this only if there is a sync connected.
        onsets = np.where(np.hstack([0,np.diff(g.astype(np.int8))])>0)[0]
        offsets = np.where(np.hstack([0,np.diff(g.astype(np.int8))])<0)[0]-1
        if (len(onsets) > len(trialmarkers)-2) & (len(onsets) < len(trialmarkers)+2): # allow to be one sync off, this is because of how the task is stopped
            # get the frametimes (prefered method)
            # right now doing this only if rig_t and frame_num[events] have the same size of be off by 1
            if (len(trialmarkers) == len(onsets)) or (len(trialmarkers)+1 == len(onsets)):
                frametimes = extrapolate_time_from_clock(trialmarkers,
                                                         frame_num[onsets[:len(trialmarkers)]],
                                                         np.arange(len(vid)))
            else:
                RuntimeWarning(f'Length of sync pulses did not match camera {len(rig_t)},{len(events)}.')
    if frametimes is None: # then it didnt work, use the comments
        # use_the_trial_onsets
        frame_num = np.array([int(re.findall("\d+,",c)[0].strip(',')) for c in list(filter(lambda x: 'start' in x, comm))])
        try: # try separated by :
            trial_num = np.array([int(re.findall(": \d+",c)[0].strip(':')) for c in list(filter(lambda x: 'start' in x, comm))])
        except Exception as err: # then the log format is different 
            print(err)
            raise(ValueError('Could not parse the trial numbers from the comments, check the file.'))
        if len(np.unique(frame_num)) == 1:
            print('The labcams network comments dont not have the frame numbers. Estimating using the frame time.')
            frame_times = np.array([float(re.findall(",[+-]?([0-9]+([.][0-9]*)?|[.][0-9])",c)[0][0]) for c in list(filter(lambda x: 'start' in x, comm))])
            frame_num = [camlog[0].values[camlog[1]>=f][0] for f in frame_times]
        trialtimes = []
        frame_nums = []
        for ii,itrial in enumerate(trial_num):
            # get the onset
            idx = np.where(trialmarkers_trials == itrial+1)[0]
            if len(idx):  # just in case not all trials are captured in the log
                trialtimes.append(trialmarkers[idx[0]])
                frame_nums.append(frame_num[ii])
        print(f'Using the frametimes from the network log. This will be approximate [cam{icam}].')
        frametimes = extrapolate_time_from_clock(trialtimes,frame_nums,np.arange(len(vid))) # assume they are the same len until we need to fix that
    events = []
    for iin,g in zip(channel_selection,gpio):
        if not len(frametimes) == len(g):
            print('The number of frames does not match the size of the gpio. there is probably an error on the camlog.')
            #assert len(frametimes) == len(g), ValueError('The size of the gpio is not the same as the number of frames, fix it.')
        events.append(dict(stream_name = f'cam{icam}',event_name=f'gpio{iin}',
                          event_timestamps = frametimes,
                          event_values = g))
    return frametimes, events

def extract_chipmunk_camera_data(folder, trial_dict):
    '''
    Extract key frames and frametimes from droplets camera recordings.

    camera, frames, events = extract_chipmunk_camera_data(folder ,trialdicts)

    Joao Couto - 2025
    ''' 
    if type(folder) is list:
        camerafiles = list(filter(lambda x: str(x).endswith('.avi'),folder))
        cameralogfiles = list(filter(lambda x: str(x).endswith('.camlog'),folder))
    else:
        camerafiles = list(Path(folder).glob('*.avi'))
        cameralogfiles = list(Path(folder).glob('*.camlog'))
    camfiles = natsorted([str(c) for c in camerafiles])
    camlogfiles = natsorted([str(c) for c in cameralogfiles])
    
    from decord import VideoReader
    camera = []
    frames = []
    events = []
    trials = pd.DataFrame(trial_dict) # convert to dataframe to handle faster to write
    conditiontrials = [] # get one random trial per condition
    timepoints = []
    a = np.where(np.isfinite(trials.t_response.values) & (trials.response.values == 1))[0]
    if len(a): 
        conditiontrials += [np.random.choice(a,1)]
        timepoints.append(trials.t_response.values[conditiontrials[-1]])
    a = np.where(np.isfinite([t if not t is None else np.nan for t in trials.t_response.values]) & (trials.response.values == -1))[0]
    if len(a):
        conditiontrials += [np.random.choice(a,1)]
        timepoints.append(trials.t_response.values[conditiontrials[-1]])
    a = np.where(np.isfinite([t if not t is None else np.nan for t in trials.t_earlywithdraw.values]) & (trials.early_withdrawal.values == 1))[0]
    if len(a): 
        conditiontrials += [np.random.choice(a,1)]
        timepoints.append(trials.t_response.values[conditiontrials[-1]])
    conditiontrials = np.hstack(conditiontrials)

    for icam,(vidfile,log) in enumerate(zip(camfiles,camlogfiles)):
        comm, camlog = read_camlog(log)
        vid = VideoReader(str(vidfile))
        try:
            frametimes, camera_events = _handle_chipmunk_camera_sync(icam, camlog, comm, vid, trial_dict)
        except Exception as err:
            print(vidfile)
            print(err)
            print(f'Skipping camera {vidfile}')
            continue
        
        events.extend(camera_events)
        videoname = f'cam{icam}'
        camera.append(dict(frame_times = frametimes,
                           frame_rate = vid.get_avg_fps(),
                           n_frames = len(vid),
                           file_path = vidfile,
                           video_name = videoname))
        # extract example frames
        #    - select a trial
        for itrial in conditiontrials:
            for t in timepoints:
                if np.isfinite(t):
                    if len(np.where(frametimes>=t)[0]):
                        frame_num = np.where(frametimes>=t)[0][0]
                        frames.append(dict(video_name = videoname,
                                           frame_num = frame_num,
                                           frame = vid[frame_num].asnumpy()))
                    else:
                        print(f'Check {videoname} in {folder}, there might be a sync issue?')
        del vid
    return camera, frames, events


def chipmunk_insert_decision_task(d, mintrials = 50):
    '''
    Inserts a chipmunk trialset into the DecisionTask tables

    Joao Couto - 2025
    '''
    import warnings
    from .pluginschema import Chipmunk
    from labdata.schema import Watering, Session, DecisionTask, Dataset
    d = (Dataset & d).fetch1()

    trials = pd.DataFrame((Chipmunk*Chipmunk.Trial*Chipmunk.TrialParameters & d).fetch(order_by='trial_num'))
    if len(trials)<50: 
        return
    trials['reward_volume'] = 0
    trials.loc[(trials['rewarded'] == 1)&(trials['response'] == 1),'reward_volume'] = trials['setting_right_reward_volume'].iloc[0]
    trials.loc[(trials['rewarded'] == 1)&(trials['response'] == -1),'reward_volume'] = trials['setting_left_reward_volume'].iloc[0]

    watering = dict(subject_name = d['subject_name'],
                watering_datetime = (Dataset*Session & d).fetch('session_datetime')[0],
                water_volume = np.sum(trials.reward_volume.values)/1000.)
    dtask = dict(d,n_total_trials = len(trials),
             n_total_assisted = 0, # there are no assisted trials for chipmunk?
             n_total_performed = np.sum((trials.early_withdrawal.values == 0) &
                                        (trials.initiated.values == 1)),
             n_total_with_choice = np.sum((trials.early_withdrawal.values == 0) &
                                          (trials.response.values != 0)),
             n_total_initiated = np.sum((trials.initiated.values == 1)),
             n_total_rewarded = np.sum((trials.early_withdrawal.values == 0) &
                                       (trials.response.values != 0) &
                                       (trials.rewarded.values == 1)),
             n_total_punished = np.sum((trials.early_withdrawal.values == 0) &
                                       (trials.response.values != 0) &
                                       (trials.punished.values == 1)),
             watering_datetime = watering['watering_datetime'])
    # separate by optogenetics trials and by modality:
    trialsets = []
    for mod in np.unique(trials.rewarded_modality.values):
        tset = trials[(trials.rewarded_modality == mod)]
        if mod == 'visual':
            stim_int = tset.stim_rate_vision.values - tset.category_boundary.values
        elif mod == 'audio':
            stim_int = tset.stim_rate_audio.values - tset.category_boundary.values
        else:
            raise(f'[chipmunk]: Not sure how to handle {mod}.')
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", category=RuntimeWarning)
            reaction_times = tset.t_response.values - tset.t_gocue.values
        reaction_times[(tset.response.values == 0)] = np.nan
        performance = np.nansum((tset.with_choice.values == 1) 
                                & (tset.rewarded == 1))/np.nansum((tset.with_choice.values == 1))
        performance_easy = np.nansum((tset.with_choice.values == 1) & 
                                  (np.abs(stim_int) == np.nanmax(stim_int)) &
                                  (tset.rewarded.values == 1))/np.nansum(
                                      (tset.with_choice.values == 1) &
                                      (np.abs(stim_int) == np.nanmax(stim_int)) &
                                      (tset.response.values != 0))
        if not np.isfinite(performance_easy):
            performance_easy = 0
        if not np.isfinite(performance):
            performance = 0 # there were no unassisted
        if len(tset)>10: # only add if there are more than 
            trialsets.append(dict(d,
                                  trialset_description = mod,
                                  n_trials = len(tset),
                                  n_performed = np.nansum((tset.initiated.values == 1)),
                                  n_with_choice = np.nansum((tset.with_choice.values == 1)),
                                  n_correct = np.nansum(~(tset.with_choice.values == 0) &
                                                     (tset.rewarded.values == 0)),
                                  performance = performance,
                                  performance_easy = performance_easy,
                                  trial_num = tset.trial_num.values,
                                  assisted = tset.with_choice.values*0, # there are no assisted
                                  response_values = [r if i==1 else np.nan for i,r in zip(tset.with_choice.values,tset.response.values)],
                                  correct_values = tset.rewarded.values,
                                  initiation_times = tset.t_initiate.values-tset.t_start.values,
                                  intensity_values = stim_int,
                                  reaction_times = reaction_times))    
    # Inserts
    Watering.insert1(watering,
                     skip_duplicates = True)
    DecisionTask.insert1(dtask,
                         skip_duplicates = True,
                         allow_direct_insert=True,
                         ignore_extra_fields=True)
    DecisionTask.TrialSet.insert(trialsets,
                                 skip_duplicates = True,
                                 allow_direct_insert=True,
                                 ignore_extra_fields=True)
