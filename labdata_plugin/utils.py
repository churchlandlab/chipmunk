from labdata.utils import *
import warnings

def _stimulus_trains(intervals, pulse_duration, extra_duration):
    """Intended onsets and duration, using the sound card's actual sample period.

    Both Chipmunk protocols generate at 192 kHz, pad channels to the longest
    train and repeat that joint waveform. These are not measured exposures.
    """
    fs = 192000
    if not np.isfinite(pulse_duration) or pulse_duration <= 0:
        raise ValueError('Missing or invalid saved stimulus pulse duration')
    if not np.isfinite(extra_duration) or extra_duration < 0:
        raise ValueError('Invalid saved extra stimulus duration')
    pulse = int(np.floor(pulse_duration * fs + 1e-9))
    if pulse < 1:
        raise ValueError('Saved stimulus pulse is shorter than one sample')
    onsets, lengths = [], []
    for isi in intervals:
        isi = np.asarray(isi, dtype=float).ravel()
        if len(isi) < 2 or not np.all(np.isfinite(isi)) or np.any(isi < 0):
            raise ValueError('Missing or invalid saved stimulus intervals')
        gaps = np.floor(isi * fs + .5).astype(np.int64)
        onsets.append(np.cumsum(gaps[:-1]) + np.arange(len(gaps)-1) * pulse)
        lengths.append(int(gaps.sum() + (len(gaps)-1) * pulse))
    period = max(lengths)
    if period <= 0:
        raise ValueError('Empty saved stimulus train')
    total = period + int(np.floor(extra_duration * fs + .5))
    trains = []
    for events in onsets:
        repeated = np.concatenate([events + repeat * period
                                   for repeat in range((total+period-1)//period)])
        trains.append(repeated[repeated < total] / fs)
    return trains, total / fs


def _passive_replay(replay, trialdata=None):
    """Replay observations on the active session clock, with zero-based source keys.

    replay is the saved PassiveReplay struct (task file or chipmunk_passive copy).
    Checks against the active trials run only when trialdata is given.
    """
    sources = np.atleast_1d(replay['sourceTrialNumbers'])
    statuses = np.atleast_1d(replay['trialStatus'])
    count = int(replay['nRequested'])
    if (len(sources) != count or len(statuses) != count
            or not np.all(np.isfinite(sources))
            or not np.all(sources == sources.astype(int))
            or np.any(sources < 1)
            or (trialdata is not None and np.any(sources > len(trialdata)))
            or len(np.unique(sources)) != count
            or int(replay['nCompleted']) != np.count_nonzero(statuses == 'completed')):
        raise ValueError('Invalid saved passive replay source references or status counts')
    for source in (sources.astype(int) if trialdata is not None else []):
        if not np.isfinite(trialdata.iloc[source-1]['PlayStimulus'][0]):
            raise ValueError('Replay source trial never reached PlayStimulus')
    raw = replay['rawEvents']
    raw = [raw] if isinstance(raw, dict) else list(raw)
    if count == 1 and not raw:
        raw = [np.array([])]
    if len(raw) != count:
        raise ValueError('Invalid saved passive replay attempt count')
    names = np.atleast_1d(replay['stateNames']).tolist()
    rows = []
    for index, events in enumerate(raw):
        if not isinstance(events, dict) or 'States' not in events:
            # Stop leaves no events for an attempt it cut short, or for ones it never
            # started. A failed attempt without events is still an error.
            if (statuses[index] == 'not_started'
                    or (statuses[index] == 'aborted' and str(replay['status']) == 'aborted')):
                continue
            raise ValueError('Passive replay has no recorded event timestamps')
        states = np.atleast_1d(events['States']).astype(float)
        times = np.atleast_1d(events['StateTimestamps']).astype(float)
        if (not np.all(np.isfinite(states)) or not np.all(states == states.astype(int))
                or np.any(states < 1) or np.any(states > len(names))
                or len(times) < len(states) or not np.all(np.isfinite(times))
                or np.any(np.diff(times) < 0)):
            raise ValueError('Invalid passive replay state timestamps')
        start = float(events['TrialStartTimestamp'])
        if not np.isfinite(start):
            raise ValueError('Invalid passive replay trial start timestamp')
        observed = {names[int(state)-1]:start + float(times[i])
                    for i,state in reversed(list(enumerate(states)))}
        if 'PlayStimulus' not in observed:
            if statuses[index] == 'completed':
                raise ValueError('Completed replay has no recorded stimulus onset')
            continue
        row = dict(passive_trial_num=index, source_trial_num=int(sources[index])-1,
                   t_sync=observed.get('Sync'), t_stim=observed['PlayStimulus'],
                   t_stim_end=observed.get('StopStimulus'))
        if ((row['t_sync'] is not None and row['t_sync'] > row['t_stim'])
                or (row['t_stim_end'] is not None and row['t_stim_end'] < row['t_stim'])
                or (rows and row['t_stim'] < rows[-1]['t_stim'])):
            raise ValueError('Passive replay times are not ordered on the session clock')
        rows.append(row)
    if rows and trialdata is not None and 'trial_start_time' in trialdata:
        active_end = _get_state_time(trialdata.iloc[-1], ['FinishTrial', 'PrepareNextTrial'], index=-1)
        if active_end is not None and rows[0]['t_stim'] < active_end:
            raise ValueError('Passive replay clock precedes the end of the active session')
    return rows


def _upsert_generated_row(table, row):
    """Refresh plugin-produced metadata without REPLACE deleting referenced rows."""
    row = {name: value for name, value in row.items() if name in table.heading.names}
    key = {name: row[name] for name in table.primary_key}
    if table & key:
        if row.keys() - key.keys():
            table.update1(row)
    else:
        table.insert1(row, allow_direct_insert=True)


def _modality_codes(values):
    """Integer modality codes (1 visual, 2 auditory, 3 audio+visual), as a new array.

    Early recordings saved string labels, loaded as str elements (a MATLAB cell
    array). Unknown labels or codes raise instead of becoming NaN. Labels are normalized for case and MATLAB character padding.
    """
    labels = {'visual': 1, 'Visual': 1, 'audio': 2, 'auditory': 2, 'Auditory': 2,
              'audio+visual': 3, 'multi-sensory': 3, 'Multi-sensory': 3}
    codes = []
    for value in np.atleast_1d(values):
        code = labels.get(value.strip().lower()) if isinstance(value, str) else value
        if isinstance(code, (str, type(None))) or code not in (1, 2, 3):
            raise ValueError(f'Unknown stimulus modality {value!r}')
        codes.append(int(code))
    return np.array(codes, dtype=int)


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
        # scipy squeezes a one-trial session's vectors and struct arrays to scalars.
        if np.size(sesdata['Modality'].tolist()) == 1:
            for field in ('TrialSettings', 'TrialDelays', 'ResponseSide', 'CorrectSide',
                          'Modality', 'StimulusDuration', 'EventDuration', 'OutcomeRecord',
                          'ActualWaitTime', 'SetWaitTime', 'PreStimDelay',
                          'TrialStartTimestamp', 'EarlyWithdrawal', 'DidNotChoose'):
                if field in sesdata.dtype.names:
                    sesdata[field][()] = np.atleast_1d(sesdata[field].tolist())
            for field in ('StimulusRate', 'InterStimulusIntervalList'):
                if field in sesdata.dtype.names:
                    sesdata[field][()] = np.asarray(sesdata[field].tolist()).reshape(1, 2)
        if 'Notes' in sesdata.dtype.names:
            notes = sesdata['Notes']
            notes = '\n'.join([f'trial:{itrial};{note}' for itrial,note in enumerate(np.atleast_1d(notes.tolist())) if len(note)])
        else:
            notes = ''
        tset = sesdata['TrialSettings'].tolist()
        if 'rigNo' in  tset.dtype.fields:
            setup_name = tset['rigNo'][0]
        else:
            setup_name = None
        if 'researcher' in  tset.dtype.fields:
            experimenter = tset['researcher'][0]
        else:
            experimenter = None
        if 'demonWeight' in tset.dtype.fields:
            weight = tset['demonWeight'][0]
        else:
            weight = np.nan

        metadata = dict(notes = notes,
                        setup_name = setup_name,
                        experimenter = experimenter,
                        weight = weight)

        tmp = sesdata['RawEvents'].tolist()
        tmp = tmp['Trial'].tolist()
        if tmp.ndim == 0:
            tmp = [tmp]
        uevents = np.unique(np.hstack([t['Events'].tolist().dtype.names for t in tmp])) #Make sure not to duplicate state definitions
        uevents = np.union1d(uevents, ['Port1In', 'Port1Out', 'Port2In', 'Port2Out', 'Port3In', 'Port3Out'])
        ustates = np.unique(np.hstack([t['States'].tolist().dtype.names for t in tmp]))
        known_rewards = {'DemonReward', 'Reward', 'DemonRewardHarvest',
                         'ObsReward', 'ObsWaitForRewardRetrieval'}
        unknown_rewards = [name for name in ustates if 'Reward' in name and name not in known_rewards]
        if unknown_rewards:
            raise ValueError(f'Unrecognized reward states: {unknown_rewards}')
        saved_settings = sesdata['SettingsFile'].tolist()
        saved_assembler = (saved_settings['smaAssembler'].tolist()
                           if 'smaAssembler' in saved_settings.dtype.names else None)
        if (not set(ustates).intersection({'DemonReward', 'Reward', 'DemonWrongChoice', 'WrongChoice'})
                and saved_assembler != 'PassiveVisualStimSMA'):
            raise ValueError('No defined task outcome states and no recognized passive assembler')
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
                 if np.size(a[b]) == 0:
                     a[b] = np.array([np.nan])
             trialevents.append(a)
             a = {u:np.array([np.nan, np.nan]) for u in ustates}
             s = t['States'].tolist()
             for b in s.dtype.names:
                     a[b] = s[b].tolist()
             trialstates.append(a)
        trialstates = pd.DataFrame(trialstates)
        trialevents = pd.DataFrame(trialevents)
        trialdata = pd.merge(trialevents,trialstates,left_index=True, right_index=True)
        for name in ('Reward', 'WrongChoice'):
            if name not in trialdata:
                trialdata[name] = [np.array([np.nan, np.nan]) for _ in range(len(trialdata))]
        ## Insert a column for DemonWrongChoice in trialdata if necessary
        #if 'DemonWrongChoice' not in trialdata.columns:
        #    trialdata.insert(trialdata.shape[1], 'DemonWrongChoice', [np.array([np.nan, np.nan])] * trialdata.shape[0])
        #Add response and stimulus train related information: correct side, rate, event occurence time stamps
        trialdata.insert(trialdata.shape[1], 'response_side', sesdata['ResponseSide'].tolist())
        trialdata.insert(trialdata.shape[1], 'correct_side', sesdata['CorrectSide'].tolist())
        #Get stim modality
        # Build new arrays: sesdata['Modality'] keeps the saved labels, which the rate fallback below reads.
        tmp_modality_numeric = _modality_codes(sesdata['Modality'].tolist())
        temp_modality = [{1: 'visual', 2: 'auditory', 3: 'audio+visual'}[m] for m in tmp_modality_numeric]
        trialdata.insert(trialdata.shape[1], 'stimulus_modality', temp_modality)
        trialdata.insert(trialdata.shape[1], 'category_boundary', sesdata['CategoryBoundary'])
        if 'StimulusRate' in sesdata.dtype.fields:
            trialdata.insert(trialdata.shape[1], 'stimulus_rate_visual', sesdata['StimulusRate'].tolist()[:,0])
            trialdata.insert(trialdata.shape[1], 'stimulus_rate_auditory', sesdata['StimulusRate'].tolist()[:,1])
        else: #Stimulus rate was not yet implemented in early versions of the task
            tmp = sesdata['nVisualEvents'].tolist().astype(float)
            tmp[np.array([isinstance(x, str) and x.strip().lower() == 'visual' for x in sesdata['Modality'].tolist()]) == False] = np.nan
            trialdata.insert(trialdata.shape[1], 'stimulus_rate_visual', tmp)
            
            tmp = sesdata['nAuditoryEvents'].tolist().astype(float)
            tmp[np.array([isinstance(x, str) and x.strip().lower() in ('audio', 'auditory') for x in sesdata['Modality'].tolist()]) == False] = np.nan
            trialdata.insert(trialdata.shape[1], 'stimulus_rate_auditory', tmp)
        
        #Reconstruct the time stamps for the individual stimuli
        event_times, train_durations = [], []
        if 'StimulusDuration' in sesdata.dtype.fields:
            event_duration = sesdata['StimulusDuration'].tolist()
        elif 'EventDuration' in sesdata.dtype.fields:
            event_duration = sesdata['EventDuration'].tolist()
        else:
            event_duration = [None] * trialdata.shape[0]
            #event_duration = [0.015]*trialdata.shape[0] #This value is hard-coded in chipmunk but can change in chipmunk_solo as of March 2026
        trialdata.insert(trialdata.shape[1], 'stimulus_event_duration', event_duration)
        #TODO: Get minimum inter stimulus interval setting -> might not be explicitly stored with the chipmunk file

        delays = sesdata['TrialDelays'].tolist()
        extra_durations = np.atleast_1d(delays['ExtraStimulusDuration'].tolist())
        for t in range(trialdata.shape[0]):
            modality = tmp_modality_numeric[t]
            channels = (0, 1) if modality == 3 else (modality-1,)
            if 'InterStimulusIntervalList' in sesdata.dtype.fields:
                intervals = [sesdata['InterStimulusIntervalList'].tolist()[t][c] for c in channels]
            else:
                intervals = [sesdata['visualIsis' if c == 0 else 'auditoryIsis'].tolist()[t] for c in channels]
            trains, duration = _stimulus_trains(intervals, event_duration[t], extra_durations[t])
            start = trialdata['PlayStimulus'][t][0]
            event_times.append(trains[0] + start)
            train_durations.append(duration)
        trialdata.insert(trialdata.shape[1], 'stimulus_event_timestamps', event_times)
        trialdata['stimulus_train_duration'] = train_durations
        trialdata.insert(trialdata.shape[1], 'stimulus_brightness', sesdata['TrialSettings'].tolist()['stimBrightness'])
        trialdata.insert(trialdata.shape[1], 'stimulus_loudness', sesdata['TrialSettings'].tolist()['stimLoudness'])

        #Insert the outcome record for faster access to the different trial outcomes
        if 'OutcomeRecord' in sesdata.dtype.fields:
            trialdata.insert(0, 'outcome_record', sesdata['OutcomeRecord'].tolist())
        else: # Re-define outcome record
            outcome_record = np.zeros([trialdata.shape[0]]) * np.nan
            outcome_record[sesdata['ResponseSide'].tolist() == sesdata['CorrectSide'].tolist()] = 1
            outcome_record[sesdata['ResponseSide'].tolist() != sesdata['CorrectSide'].tolist()] = 0
            outcome_record[sesdata['EarlyWithdrawal'].tolist()] = -1
            outcome_record[sesdata['DidNotChoose'].tolist()] = 2
        try:
            tmp = sesdata['TrialDelays'].tolist()
            for key in tmp[0].dtype.fields.keys(): #Find all the keys and extract the data associated with them
                tmp_delay = tmp[key].tolist()
                trialdata.insert(trialdata.shape[1], key , tmp_delay)
        except Exception as err:
            print('[chipmunk]: For this version of chipmunk the task delays struct was not implemented yet.\nDid not generate the respective columns in the data frame.')

        trialdata.insert(trialdata.shape[1], 'required_wait_time', sesdata['SetWaitTime'].tolist())
        tmp = sesdata['ActualWaitTime'].tolist()
        trialdata.insert(trialdata.shape[1], 'actual_wait_time' , tmp)
        trialdata.insert(trialdata.shape[1], 'pre_stim_delay', sesdata['PreStimDelay'].tolist())
        if 'wrongPunishTimeout' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'incorrect_choice_timeout', sesdata['TrialSettings'].tolist()['wrongPunishTimeout'].tolist())
        elif 'PunishDuration' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'incorrect_choice_timeout', sesdata['TrialSettings'].tolist()['PunishDuration'].tolist())
        if 'earlyPunishTimeout' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'early_withdrawal_timeout', sesdata['TrialSettings'].tolist()['earlyPunishTimeout'].tolist())
        elif 'EarlyPunishDuration' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'early_withdrawal_timeout', sesdata['TrialSettings'].tolist()['EarlyPunishDuration'].tolist())
        if 'antiBiasStrength' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'anti_bias_strength', sesdata['TrialSettings'].tolist()['antiBiasStrength'].tolist())
        elif 'UseAntiBias' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'anti_bias_strength', sesdata['TrialSettings'].tolist()['UseAntiBias'].tolist())
        if 'antiBiasTau' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'anti_bias_tau', sesdata['TrialSettings'].tolist()['antiBiasTau'].tolist())
        elif 'AntiBiasTau' in sesdata['TrialSettings'].tolist().dtype.fields:
            trialdata.insert(trialdata.shape[1], 'anti_bias_tau', sesdata['TrialSettings'].tolist()['AntiBiasTau'].tolist())
        if 'propLeft' in sesdata['TrialSettings'].tolist().dtype.fields:
             trialdata.insert(trialdata.shape[1], 'proportion_left', sesdata['TrialSettings'].tolist()['propLeft'].tolist())
        elif 'PropLeft' in sesdata['TrialSettings'].tolist().dtype.fields:
             trialdata.insert(trialdata.shape[1], 'proportion_left', sesdata['TrialSettings'].tolist()['PropLeft'].tolist())
        trialdata.insert(trialdata.shape[1], 'pre_stim_delay_min' ,sesdata['TrialSettings'].tolist()['preStimDelayMin'].tolist())
        trialdata.insert(trialdata.shape[1], 'pre_stim_delay_max' ,sesdata['TrialSettings'].tolist()['preStimDelayMax'].tolist())
        trialdata.insert(trialdata.shape[1], 'pre_stim_delay_lambda' ,sesdata['TrialSettings'].tolist()['preStimDelayLambda'].tolist())
        if 'isPoissonStim' in sesdata['TrialSettings'].tolist().dtype.fields:
             trialdata.insert(trialdata.shape[1], 'is_poisson', sesdata['TrialSettings'].tolist()['isPoissonStim'].tolist())
        elif 'IsPoissonStim' in sesdata['TrialSettings'].tolist().dtype.fields:
             trialdata.insert(trialdata.shape[1], 'is_poisson', sesdata['TrialSettings'].tolist()['IsPoissonStim'].tolist())
        min_isi = 0.025  # Legacy tasks did not save this fixed setting.
        for field in ('MinInterval', 'minimumInterStimulusInterval', 'minInterStimulusInterval'):
            if field in sesdata.dtype.fields:
                min_isi = sesdata[field].tolist()
                break
        trialdata.insert(trialdata.shape[1], 'min_isi', min_isi)

        #TEMPORARY: import the demonstrator and observer id
        tmp = sesdata['TrialSettings'].tolist()
        if 'demonID' in tmp.dtype.fields:
            trialdata.insert(trialdata.shape[1], 'demonstrator_ID' , tmp['demonID'].tolist())
        else: #The subject ID was not explicitly tracked within the data structure initially
            trialdata.insert(trialdata.shape[1], 'demonstrator_ID' , os.path.split(file_name)[1].split('_')[0]) #Use the identifier contained in the file name
        
        #Add a generic state tracking the timing of outcome presentation, this is also a 1d array of two elements
        if 'DemonCorrectChoice' in trialdata.keys(): # This is the chipmunk version with omissions
            outcome_name = ['DemonCorrectChoice', 'DemonWrongChoice']
        elif 'DemonReward' in trialdata.keys():
            outcome_name = ['DemonReward']
            if 'DemonWrongChoice' in trialdata.keys():
                outcome_name.append('DemonWrongChoice')
            else:
                print('[chipmunk]: There is no DemonWrongChoice... Using FinishTrial')
                outcome_name.append('FinishTrial')
        else:
            outcome_name = ['Reward', 'WrongChoice']
        outcome_timing = []
        for k in range(trialdata.shape[0]):
            if np.isnan(trialdata[outcome_name[0]][k][0]) == 0:
                outcome_timing.append(np.array([trialdata[outcome_name[0]][k][0], trialdata[outcome_name[0]][k][0]]))
            elif np.isnan(trialdata[outcome_name[1]][k][0]) == 0:
                outcome_timing.append(np.array([trialdata[outcome_name[1]][k][0],trialdata[outcome_name[1]][k][0]]))
            else:
                outcome_timing.append(np.array([np.nan, np.nan]))
        trialdata.insert(trialdata.shape[1], 'outcome_presentation', outcome_timing)
        # Retrieve the flag for revised choices
        if 'ReviseChoiceFlag' in sesdata.dtype.names:
            trialdata.insert(trialdata.shape[1], 'revise_choice_flag', np.ones(trialdata.shape[0], dtype = bool) * sesdata['ReviseChoiceFlag'].tolist())
        else:
            print('[chipmunk]: There was no ReviseChoiceFlag.')
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

            if np.isnan(trialdata[outcome_name[0]][k][0]) == 0:
                outcome_end.append(np.array([trialdata['response_port_out'][k][0], trialdata['response_port_out'][k][0]]))
            elif np.isnan(trialdata[outcome_name[1]][k][0]) == 0:
                if 'FinishTrial' in sesdata.dtype.fields: # this outcome_end is legacy?
                    outcome_end.append(np.array([trialdata['FinishTrial'][k][0],trialdata['FinishTrial'][k][0]]))
                else:
                    outcome_end.append(np.array([np.nan, np.nan]))
            else:
                outcome_end.append(np.array([np.nan, np.nan]))
        trialdata.insert(trialdata.shape[1], 'outcome_end', outcome_end)
        if 'ObsOutcomeRecord' in sesdata.dtype.fields:
            trialdata.insert(1, 'observer_outcome_record', sesdata['ObsOutcomeRecord'].tolist())
            tmp = sesdata['ObsActualWaitTime'].tolist()
            trialdata.insert(trialdata.shape[1], 'observer_actual_wait_time' , tmp)
            tmp = sesdata['TrialSettings'].tolist()
            trialdata.insert(trialdata.shape[1], 'dobserver_ID' , tmp['obsID'].tolist())
        if 'PassiveReplay' in sesdata.dtype.names:
            from scipy.io import loadmat
            replay = loadmat(file_name, simplify_cells=True)['SessionData']['PassiveReplay']
            metadata['passive_trials'] = _passive_replay(replay, trialdata)
            metadata['passive_replay'] = dict(status=str(replay['status']),
                                               stoppedPulseAfter=replay.get('stoppedPulseAfter', []))

    except Exception as err:
        raise ValueError(f'[chipmunk]: Could not load {file_name}: {err}') from err
    return trialdata,sesdata,metadata

def _get_state_time(trial, states = [],index = 0, *, exact=False):
    if not len(states):
        return None
    if type(states) is str:
        states = [states]
    time =  np.nan # in case the state does not exist..
    for state in states:
        statekeys = [k for k in trial.keys() if (state == k if exact else state in k)]
        if len(statekeys):
            if trial[statekeys[0]] is not None:                
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

def _read_setting(session_data, setting_name):
    ''' 
    This is to resolve inconsistencies in the filenames.
    Please don't change the case spelling of variables.
    '''
    settings = session_data['SettingsFile'].tolist()    
    if setting_name in settings.dtype.names:
        return settings[setting_name].tolist()
    else: # try capitalizing the first letter..
        set_name = setting_name[0].upper() + setting_name[1:] 
        if set_name in settings.dtype.names:
            return settings[set_name].tolist()
        else:
            print('Could not find setting name')
            return None


def _configured_reward_volume(value):
    """A saved calibration target in uL; empty/NaN means unknown, never measured."""
    value = np.asarray(value)
    if value.size == 0:
        return None
    if value.size != 1 or value.dtype.kind not in 'iuf':
        raise ValueError('Invalid configured reward volume: expected one numeric value')
    volume = float(value.reshape(-1)[0])
    if np.isnan(volume):
        return None
    if not np.isfinite(volume) or volume < 0:
        raise ValueError('Invalid configured reward volume: must be finite and nonnegative')
    return volume


def process_chipmunk_file(filepath):
    trialdata,session_data,metadata = load_chipmunk_trialdata(filepath)
    if trialdata is None:
        raise ValueError(f'Could not parse Chipmunk file: {filepath}')

    # process settings from the entire session
    setting_high_rate_side = 'right' if (session_data['SettingsFile'].tolist())['highRateSide'] == 'R' else 'left'
    setting_prob_audio = _read_setting(session_data, 'propOnlyAuditory')
    setting_prob_vision = _read_setting(session_data,'propOnlyVisual')
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
        
    
    # TaskPhase is an experiment/settings label, not a verified assembler identity.
    settings = session_data['SettingsFile'].tolist()
    assembler = settings['smaAssembler'].tolist() if 'smaAssembler' in settings.dtype.names else None
    stops_on_nochoice = assembler in (
        'DemonstratorTaskSMA', 'DemonstratorTaskStopStimSMA',
        'DemonstratorFixationTrainingSMA', 'FreelyMovingObsDemonstratorTaskSMA',
        'ObserverTaskSMA', 'NonSocialObserverTaskSMA',
        'FreelyMovingNonSocialObserverTaskSMA', 'ObserverFixationTrainingSMA',
        'MultipleModalitiesTaskSMA')

    passive = assembler == 'PassiveVisualStimSMA'
    # Legacy files without an assembler retain task inference; passive identity is unverified.
    tset = np.atleast_1d(session_data['TrialSettings'].tolist()).reshape(-1)
    if len(tset) != len(trialdata):
        raise ValueError('TrialSettings count does not match saved trials')
    if 'smaAssembler' in tset.dtype.names:
        for saved in tset['smaAssembler']:
            saved = np.asarray(saved)
            if saved.size != 1 or saved.item() != assembler:
                raise ValueError('Inconsistent per-trial smaAssembler')
    left_volumes = [_configured_reward_volume(v) for v in tset['leftRewardVolume']]
    right_volumes = [_configured_reward_volume(v) for v in tset['rightRewardVolume']]
    setting_left_reward_volume = left_volumes[0]
    setting_right_reward_volume = right_volumes[0]
    if setting_left_reward_volume is None or setting_right_reward_volume is None:
        raise ValueError('Unknown trial-zero reward volume; session setting columns are NOT NULL')
    
    # Chipmunk Solo 986bd21+: saved active trials before the unsaved pulse of a trial cut short by Stop.
    stopped_trial_pulse = None
    if 'StoppedTrialPulse' in session_data.dtype.names:
        stopped = np.asarray(session_data['StoppedTrialPulse'].tolist(), dtype=float).ravel()
        if stopped.size and (stopped.size != 1 or not np.isfinite(stopped[0])
                             or stopped[0] != int(stopped[0]) or stopped[0] != len(trialdata)):
            raise ValueError('Invalid StoppedTrialPulse marker for saved active trials')
        stopped_trial_pulse = int(stopped[0]) if stopped.size else None

    settings_dict = dict(stopped_trial_pulse = stopped_trial_pulse,
                         setting_modalities = setting_modalities,
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
                          t_start = _get_state_time(trial,['WaitForCenterFixation','GoToCenter','DemonTrialStart', 'TrialStart']),
                          t_sync = _get_state_time(trial,'Sync'),         
                          t_initiate = _get_state_time(trial,['InitFixation','DemonInitFixation']),
                          t_earlywithdraw = _get_state_time(trial,['EarlyWithdrawal','DemonEarlyWithdrawal']), 
                          t_stim = _get_state_time(trial,'PlayStimulus'),
                          t_gocue = _get_state_time(trial,['WaitForWithdrawalFromCenter','DemonWaitForWithdrawalFromCenter']),
                          t_react = _get_state_time(trial,['WaitForResponse','DemonWaitForResponse']),
                          t_response = _get_state_time(trial,['DemonReward','Reward','DemonWrongChoice','WrongChoice'], exact=True),
                          t_response_port_out = _get_state_time(trial, 'response_port_out'),
                          t_end = _get_state_time(trial,['FinishTrial','PrepareNextTrial']))
        stim_duration = trial.get('stimulus_train_duration', 1. + trial['ExtraStimulusDuration'])
        if not trialtimes['t_earlywithdraw'] is None:
            # trim the stim duration to the withdrawal time
            if not trialtimes['t_stim'] is None:
                stim_duration = np.min([stim_duration,trialtimes['t_earlywithdraw']-trialtimes['t_stim']])
            else:
                stim_duration = 0
        if not trialtimes['t_response'] is None:
            # trim the stim duration to the withdrawal time
            stim_duration = np.min([stim_duration,trialtimes['t_response']-trialtimes['t_stim']])
        # Only verified producers send SoftCode 255 on no choice.
        t_nochoice = _get_state_time(trial, ['DemonDidNotChoose','DidNotChoose']) if stops_on_nochoice else None
        if t_nochoice is not None and trialtimes['t_stim'] is not None:
            stim_duration = np.min([stim_duration, t_nochoice - trialtimes['t_stim']])
        if trialtimes['t_initiate'] is None and trialtimes['t_stim'] is None:
            stim_duration = 0.

        response = -1 if trial.response_side == 0 else 0
        response = 1 if trial.response_side == 1 else response
        
        trials_dict.append(dict(trialtimes,
                                stim_duration = stim_duration,
                                left_poke = _get_port(trial,'Port1'),
                                center_poke = _get_port(trial,'Port2'),
                                right_poke = _get_port(trial,'Port3'),
                                initiated = 1 if not _get_state_time(trial, states = 'InitFixation') is None else 0,
                                rewarded = 1 if not _get_state_time(trial, states = ['DemonReward', 'Reward'], exact=True) is None else 0,
                                punished = 1 if not _get_state_time(trial, states = 'WrongChoice') is None else 0,
                                early_withdrawal = 1 if not _get_state_time(trial, states = 'EarlyWithdrawal') is None else 0,
                                with_choice = 0 if trialtimes['t_response'] is None else 1,
                                response = response))
        modality = None
        if trial.stimulus_modality == 'auditory':
            modality = 'audio'
        elif trial.stimulus_modality == 'visual':
            modality = 'visual'
        elif trial.stimulus_modality in ['multisensory','audio+visual']:
            modality = 'visual+audio'
        else:
            raise(ValueError(f'[chipmunk]: Unknown modality {trial.stimulus_modality}'))
        
        if trial.correct_side not in (0, 1):
            raise ValueError('Invalid correct side: expected 0 (left) or 1 (right)')
        configured_volume = (right_volumes if trial.correct_side == 1 else left_volumes)[itrial]
        trial_settings_dict.append(dict(trial_num = itrial,
                                        configured_reward_volume = None if passive else configured_volume,
                                        rewarded_modality = modality,
                                        stim_rate_audio = trial.stimulus_rate_auditory if np.isfinite(trial.stimulus_rate_auditory) else None,
                                        stim_rate_vision = trial.stimulus_rate_visual if np.isfinite(trial.stimulus_rate_visual) else None,
                                        category_boundary = trial.category_boundary,
                                        rewarded_position = 'right' if trial.correct_side == 1 else 'left',
                                        stim_events = [f for f in trial.stimulus_event_timestamps],
                                        stim_event_duration = trial.stimulus_event_duration,
                                        min_isi = trial.min_isi,
                                        is_poisson = trial.is_poisson,
                                        stim_brightness = trial.stimulus_brightness,
                                        stim_loudness = trial.stimulus_loudness,
                                        extra_stim_duration = trial.ExtraStimulusDuration,
                                        proportion_left = trial.proportion_left,
                                        anti_bias_strength = trial.anti_bias_strength,
                                        anti_bias_tau = trial.anti_bias_tau,
                                        pre_stim_delay_min = trial.pre_stim_delay_min,
                                        pre_stim_delay_max= trial.pre_stim_delay_max,
                                        pre_stim_delay_lambda = trial.pre_stim_delay_lambda,
                                        pre_stim_delay = trial.pre_stim_delay,
                                        required_wait_time = trial.required_wait_time,
                                        incorrect_choice_timeout = trial.incorrect_choice_timeout,
                                        early_withdrawal_timeout = trial.early_withdrawal_timeout))
    max_stims = np.max([len(np.unique([t['stim_rate_audio'] 
                                   for t in trial_settings_dict 
                                   if not t['stim_rate_audio'] is None])),
                    len(np.unique([t['stim_rate_vision'] 
                                   for t in trial_settings_dict 
                                   if not t['stim_rate_vision'] is None]))])
    settings_dict['setting_task_mode'] = 'passive' if passive else ('detection' if max_stims <= 2 else 'discrimination')
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

def _session_sync_times(trials, passive_trials=()):
    """All recorded Bpod sync pulses, including replay, on the session clock."""
    times = np.asarray([row['t_sync'] for row in [*trials, *passive_trials]], dtype=float)
    if not np.all(np.isfinite(times)) or np.any(np.diff(times) <= 0):
        raise ValueError('Session sync timestamps must be finite and strictly increasing')
    return times


def _bpod_sync_pulse_numbers(n_active, n_passive, stopped_trial_pulse=None):
    """Hardware pulse number of each saved Bpod sync pulse (active, then replay).

    A trial cut short by Stop is not saved, but its Sync state already sent a
    pulse: Bpod's RunStateMachine (1.80, all rigs) sends 'R' and reads the
    trial-start timestamp before its loop, and returns empty events only when
    Stop arrives inside that loop. chipmunk_solo writes StoppedTrialPulse only
    on that path, so replay pulses sit one number later. Downstream pairing
    checks pulse intervals, so a wrong marker fails instead of shifting replays.
    """
    if stopped_trial_pulse is not None and stopped_trial_pulse != n_active:
        raise ValueError(f'Stopped-trial pulse after {stopped_trial_pulse} saved trials, '
                         f'but {n_active} active trials were saved')
    gap = int(stopped_trial_pulse is not None and n_passive > 0)
    return np.r_[np.arange(n_active), np.arange(n_passive) + n_active + gap]


def _replay_gpio_onsets(channels, t, trialmarkers, n_active, stopped_trial_pulse=None, passive_replay=None):
    """Require a unique interval-supported mapping across all GPIO channels.

    Markers allow an unsaved pulse after active trials or at the end of an
    aborted replay. A camera can miss a pulse that Stop cut short, so the marked
    pulse may be absent. Other omissions are checked for ambiguity, never
    accepted as evidence of sync. Tolerance remains unvalidated on hardware.
    """
    from itertools import combinations
    t = np.asarray(t, dtype=float)
    trialmarkers = np.asarray(trialmarkers, dtype=float)
    for values in (t, trialmarkers):
        if (values.ndim != 1 or len(values) < 2 or not np.isfinite(values).all()
                or np.any(np.diff(values) <= 0)):
            raise ValueError('Camera alignment needs finite increasing frame and Bpod times')
    n = len(trialmarkers)
    if not isinstance(n_active, (int, np.integer)) or not 0 <= n_active <= n:
        raise ValueError('Invalid active trial count')
    if stopped_trial_pulse is not None and stopped_trial_pulse != n_active:
        raise ValueError(f'Stopped-trial pulse after {stopped_trial_pulse} saved trials, '
                         f'but {n_active} active trials were saved')
    trailing = False
    if passive_replay is not None:
        marker = np.asarray(passive_replay.get('stoppedPulseAfter', []), dtype=float).ravel()
        if marker.size:
            if (marker.size != 1 or not np.isfinite(marker[0]) or marker[0] != int(marker[0])
                    or not 0 <= marker[0] <= n - n_active
                    or passive_replay.get('status') != 'aborted'):
                raise ValueError('Invalid replay stoppedPulseAfter metadata')
            trailing = bool(marker[0] == n - n_active)
    bpod = np.diff(trialmarkers)
    frame_period = np.median(np.diff(t))
    found, permitted, reasons = [], [], []
    for iin, g in channels:
        g = np.asarray(g)
        if g.shape != t.shape or not np.isin(g, (0, 1)).all():
            raise ValueError(f'gpio{iin} must contain one binary state per camera frame')
        if g[0]:
            raise ValueError(f'gpio{iin} is initially high; first sync edge is unknown')
        onsets = np.flatnonzero(np.diff(g.astype(np.int8), prepend=0) > 0)
        extra = len(onsets) - n
        allowed = {()}
        if stopped_trial_pulse is not None:
            allowed.add((n_active,))
        if trailing:
            allowed.add((len(onsets) - 1,))
            if stopped_trial_pulse is not None:
                allowed.add((n_active, len(onsets) - 1))
        # At most one stopped-task and one stopped-replay pulse can be unsaved.
        if not 0 <= extra <= (stopped_trial_pulse is not None) + trailing:
            reasons.append(f'gpio{iin} has {len(onsets)} pulses, expected {n} plus marked stops')
            continue
        for omitted in combinations(range(len(onsets)), extra):
            reading = np.delete(onsets, omitted)
            error = np.abs(np.diff(t[reading]) - bpod)
            if np.any(error > 2 * frame_period + 0.001 * bpod):
                continue
            found.append((iin, reading))
            if omitted in allowed:
                permitted.append(reading)
        reasons.append(f'gpio{iin} pulse intervals disagree with Bpod or require an unmarked omission')
    if len(found) > 1 and any(not np.array_equal(found[0][1], o) for _, o in found[1:]):
        raise ValueError('Replay camera alignment is ambiguous: distinct fitting mappings across GPIO channels '
                         '(frame period may be too coarse)')
    if not permitted:
        raise ValueError('Replay camera alignment requires matching GPIO sync pulses: '
                         + ('; '.join(reasons) if reasons else 'no GPIO channel changes'))
    return permitted[0]


def _handle_chipmunk_camera_sync(icam, camlog, comm, vid, trialdicts, passive_trials=(), stopped_trial_pulse=None, passive_replay=None):
    '''
    Handles the camera sync for the chipmunk task. 
    These frametimes may have to be interpolated when .

    Returns interpolated frametimes and events

    frametimes, events = _handle_chipmunk_camera_sync(icam, camlog, comm, vid, trialdicts)

    Joao Couto - 2025
    '''

    trialmarkers = _session_sync_times(trialdicts, passive_trials)
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
    if passive_trials or passive_replay is not None:
        # Replay sessions must match exactly; the loop below keeps its tolerance for other sessions.
        onsets = _replay_gpio_onsets(zip(channel_selection, gpio), t, trialmarkers,
                                     len(trialdicts), stopped_trial_pulse, passive_replay)
        frametimes = extrapolate_time_from_clock(trialmarkers, frame_num[onsets], np.arange(len(vid)))
    for iin,g in ([] if passive_trials or passive_replay is not None else zip(channel_selection,gpio)):
        # do this only if there is a sync connected.
        onsets = np.where(np.hstack([0,np.diff(g.astype(np.int8))])>0)[0]
        offsets = np.where(np.hstack([0,np.diff(g.astype(np.int8))])<0)[0]-1
        if (len(onsets) > len(trialmarkers)-2) & (len(onsets) < len(trialmarkers)+2):
            # allow to be one sync off, this is because of how the task is stopped
            # get the frametimes (prefered method)
            # right now doing this only if rig_t and frame_num[events] have the same size of be off by 1
            if (len(trialmarkers) == len(onsets)) or (len(trialmarkers)+1 == len(onsets)):
                frametimes = extrapolate_time_from_clock(trialmarkers,
                                                         frame_num[onsets[:len(trialmarkers)]],
                                                         np.arange(len(vid)))
            else:
                warnings.warn(f'Camera sync pulse count {len(onsets)} does not match Bpod {len(trialmarkers)}.')
    if frametimes is None and (passive_trials or passive_replay is not None):
        raise ValueError('Replay camera alignment requires matching GPIO sync pulses')
    if frametimes is None: # then it didnt work, use the comments
        # use_the_trial_onsets
        frame_num = np.array([int(re.findall(r"\d+,",c)[0].strip(',')) for c in list(filter(lambda x: 'start' in x, comm))])
        try: # try separated by :
            trial_num = np.array([int(re.findall(r": \d+",c)[0].strip(':')) for c in list(filter(lambda x: 'start' in x, comm))])
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

def extract_chipmunk_camera_data(folder, trial_dict, passive_trials=(), stopped_trial_pulse=None, passive_replay=None):
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
    response_times = np.asarray([np.nan if t is None else t for t in trials.t_response], dtype=float)
    withdrawal_times = np.asarray([np.nan if t is None else t for t in trials.t_earlywithdraw], dtype=float)
    conditiontrials = [] # get one random trial per condition
    timepoints = []
    a = np.where(np.isfinite(response_times) & (trials.response.values == 1))[0]
    if len(a): 
        conditiontrials += [np.random.choice(a,1)]
        timepoints.append(trials.t_response.values[conditiontrials[-1]])
    a = np.where(np.isfinite(response_times) & (trials.response.values == -1))[0]
    if len(a):
        conditiontrials += [np.random.choice(a,1)]
        timepoints.append(trials.t_response.values[conditiontrials[-1]])
    a = np.where(np.isfinite(withdrawal_times) & (trials.early_withdrawal.values == 1))[0]
    if len(a): 
        conditiontrials += [np.random.choice(a,1)]
        timepoints.append(withdrawal_times[conditiontrials[-1]])
    conditiontrials = np.hstack(conditiontrials) if conditiontrials else np.array([], dtype=int)

    for icam,(vidfile,log) in enumerate(zip(camfiles,camlogfiles)):
        comm, camlog = read_camlog(log)
        try:
            vid = VideoReader(str(vidfile))
        except Exception as err:
            continue # skip ahead
            # re-encode the video?
            if 'broken metadata': # re-encode the video
                print(f'[chipmunk]: Video had broken metadata, re-encoding {vidfile}.')
                output = Path(vidfile).with_suffix(".metadata.avi")
                cmd = f'ffmpeg -i {vidfile} -r 30 -enc_time_base -1 -bf 0 -c:v libx264 -preset slow -pix_fmt yuv420p -vsync 2 -c:a copy {output}'
                print(cmd)
                os.system(cmd) # re-encode the video using ffmpeg. Note that this may drop frames if some are missing in the original data
                vid = VideoReader(str(output))
        try:
            frametimes, camera_events = _handle_chipmunk_camera_sync(icam, camlog, comm, vid, trial_dict, passive_trials, stopped_trial_pulse, passive_replay)
        except Exception as err:
            print(vidfile)
            print(err)
            if passive_trials or passive_replay is not None:
                raise ValueError(f'Replay camera alignment failed for {vidfile}') from err
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
    if trials.empty or trials['setting_task_mode'].iloc[0] == 'passive':
        return
    volumes = trials['configured_reward_volume'].copy()
    missing = volumes.isna()
    if missing.any():
        warnings.warn('[chipmunk]: Missing configured reward volume; estimating from '
                      'trial-zero correct-side settings (not measured water).')
        for index in trials.index[missing]:
            side = trials.at[index, 'rewarded_position']
            if side not in ('left', 'right'):
                raise ValueError(f'Invalid rewarded position: {side!r}')
            volumes.at[index] = trials.at[index, f'setting_{side}_reward_volume']
    volumes = [_configured_reward_volume(v) for v in volumes]
    if any(v is None for v in volumes):
        raise ValueError('Cannot estimate water with unknown trial-zero reward volume')
    trials['reward_volume'] = trials['rewarded'] * np.asarray(volumes)

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
        if len(trials) < mintrials or len(tset) <= 10:
            continue
        if mod == 'visual':
            stim_int = tset.stim_rate_vision.values - tset.category_boundary.values
        elif mod == 'audio':
            stim_int = tset.stim_rate_audio.values - tset.category_boundary.values
        elif mod == 'visual+audio': # take vision because these should be congruent.
            stim_int = tset.stim_rate_vision.values - tset.category_boundary.values
        else:
            raise(ValueError(f'[chipmunk]: Not sure how to handle {mod}.'))
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", category=RuntimeWarning)
            reaction_times = tset.t_response.values - tset.t_gocue.values
        reaction_times[(tset.response.values == 0)] = np.nan
        performance = np.nansum((tset.with_choice.values == 1) 
                                & (tset.rewarded == 1))/np.nansum((tset.with_choice.values == 1))
        performance_easy = np.nansum((tset.with_choice.values == 1) & 
                                  (np.abs(stim_int) == np.nanmax(np.abs(stim_int))) &
                                  (tset.rewarded.values == 1))/np.nansum(
                                      (tset.with_choice.values == 1) &
                                      (np.abs(stim_int) == np.nanmax(np.abs(stim_int))) &
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
                                  n_correct = np.nansum((tset.with_choice.values == 1) &
                                                     (tset.rewarded.values == 1)),
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
    water_key = {name: watering[name] for name in Watering.primary_key}
    if (Watering & water_key) and not (DecisionTask & d & water_key):
        warnings.warn(f'[chipmunk]: Kept existing unlinked watering for {water_key}.')
        # Keep it unlinked so a later retry cannot mistake a manual record for ours.
        dtask['watering_datetime'] = None
    elif (Watering & water_key) and not np.isclose(
            (Watering & water_key).fetch('water_volume')[0], watering['water_volume'],
            rtol=1e-6, atol=1e-9):
        warnings.warn(f'[chipmunk]: Kept existing linked watering for {water_key}; estimate differs.')
    else:
        _upsert_generated_row(Watering, watering)
    _upsert_generated_row(DecisionTask, dtask)
    for trialset in trialsets:
        _upsert_generated_row(DecisionTask.TrialSet, trialset)
