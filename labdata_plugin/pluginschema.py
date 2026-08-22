import numpy as np
from labdata.schema import *

username = prefs['database']['database.user']
chipmunkschema = get_user_schema()  # allows user defined schemas
if 'chipmunk_schema' in prefs: # to be able to override to another name
    chipmunkschema = prefs['chipmunk_schema']
if type(chipmunkschema) is str: 
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
    
    from typing import no_type_check
    @no_type_check
    def make(self, key, **_kwargs):
        localpath = prefs['local_paths'][0]
        if key['dataset_name'] == 'chipmunk':
            filekey = (Dataset.DataFiles() & key & 'file_path LIKE "%.mat"').fetch(as_dict= True)
            if not len(filekey):
                RuntimeWarning(f'[chipmunk]: Dataset does not contain the log file {key}')  # noqa: PLW0133
                return
            filename = None  # noqa: F841
            local = None  # noqa: F841
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
                computer_name = str(metadata['setup_name'])
                if not computer_name in Setup().fetch('setup_name'):
                    locations = SetupLocation().fetch(as_dict = True)
                    if len(locations):
                        Setup.insert1(dict(locations[0],setup_name = computer_name,setup_description = 'Added automatically.'))
                    else:
                        computer_name = None
            user_name = None
            if not metadata['experimenter'] is None:
                if metadata['experimenter'] == 'HM': # fix hanna marsi label
                    metadata['experimenter'] = 'Marsi'
                elif metadata['experimenter'] == 'LY': # fix Letizia label
                    metadata['experimenter'] = 'Letizia'
                elif metadata['experimenter'] == 'XL': # fix Xinyan label
                    metadata['experimenter'] = 'Xinyan'
                elif metadata['experimenter'] == 'Marvion': # fix Marvin label
                    metadata['experimenter'] = 'Marvin'
                elif metadata['experimenter'] == 'GRB': # fix Gabriel label
                    metadata['experimenter'] = 'Gabriel'
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
            notes = metadata['notes'] if not metadata['notes'] == '' else None  # noqa: SIM201
            if not notes is None:
                ses = (Session() & (Dataset & key)).fetch1()
                if dset['note_datetime'] is None:
                    if user_name is None:
                        LabMember().insert1(dict(user_name = 'unknown',date_joined = '2001-1-1'),skip_duplicates = True)  # noqa: C408
                        user_name = 'unknown'
                    note = dict(note_datetime = ses['session_datetime'],  # noqa: C408
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
                dset['setup_name'] = str(computer_name)
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
                storage = (File() & dict(file_path = c['file_path'])).fetch('storage')  # noqa: C408
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
            
            if 'LABDATA_DELETE_FILES_AFTER_POPULATE' in os.environ.keys():  # noqa: SIM118
                [os.unlink(f) for f in filenames]
                print('Deleted files after populating because "LABDATA_DELETE_FILES_AFTER_POPULATE" is defined.')

    @classmethod
    def trial_query(cls, **key):
        """Return complete Chipmunk trial rows restricted by key."""
        return cls * cls.Trial * cls.TrialParameters & key

    @classmethod
    def fit_psychometric(cls, rewarded_modality='visual', min_choices=100,
                         min_required_stim_values=6, **key):
        """Fit choices from stored trials without saving a derived table."""
        from fit_psychometric import fit_psychometric

        if rewarded_modality not in ('visual', 'audio', 'visual+audio'):
            raise ValueError(f'Unknown rewarded modality {rewarded_modality!r}.')
        stim_field = ('stim_rate_audio' if rewarded_modality == 'audio'
                      else 'stim_rate_vision')
        stim_rate, category_boundary, response = (
            cls.trial_query(**key) & {'rewarded_modality': rewarded_modality}
        ).fetch(stim_field, 'category_boundary', 'response',
                order_by='trial_num')

        stim_rate = np.asarray(stim_rate, dtype=float)
        category_boundary = np.asarray(category_boundary, dtype=float)
        response = np.asarray(response, dtype=float)
        valid = (np.isfinite(stim_rate) & np.isfinite(category_boundary)
                 & np.isin(response, (-1, 1)))
        if np.sum(valid) < min_choices:
            return None

        fit = fit_psychometric(
            stim_rate[valid] - category_boundary[valid],
            (response[valid] == 1).astype(float),
            min_required_stim_values=min_required_stim_values,
        )
        return fit if fit['fit_params'] is not None else None

    @classmethod
    def trial_events(cls, is_nidq=False,
                     observation_window='center_exit', **key):
        """Return visual trials with Bpod or NIDQ event times."""
        if observation_window not in ('center_exit', 'response'):
            raise ValueError(
                "observation_window must be 'center_exit' or 'response'."
            )

        rows = list((
            cls.trial_query(**key) & {'rewarded_modality': 'visual'}
        ).fetch(
            'subject_name', 'session_name', 'dataset_name', 'trial_num',
            'stim_events', 'stim_rate_vision', 'response', 't_sync', 't_react',
            't_response', as_dict=True,
            order_by='subject_name, session_name, dataset_name, trial_num'))
        trials = []

        if is_nidq:
            sessions = sorted({
                (row['subject_name'], row['session_name']) for row in rows
            })
            event_mapping = dj.FreeTable(
                chipmunkschema.connection,
                f'`{chipmunkschema.database}`.`#event_mapping`')
            mapping_rows = list(event_mapping.fetch(as_dict=True))
            required_roles = {
                'visual_stim', 'trial_start', 'left_port', 'center_port',
                'right_port'}

            for subject_name, session_name in sessions:
                session_rows = [
                    row for row in rows
                    if row['subject_name'] == subject_name
                    and row['session_name'] == session_name]
                restriction = {
                    'subject_name': subject_name, 'session_name': session_name}
                available = {
                    (row['dataset_name'], row['stream_name'], row['event_name'])
                    for row in (
                        DatasetEvents.Digital()
                        & (EphysRecording() & restriction)
                    ).fetch('dataset_name', 'stream_name', 'event_name',
                            as_dict=True)}

                source_keys = None
                for stream_name in ('obx', 'nidq'):
                    mapping = {
                        row['event_role']: row['event_name']
                        for row in mapping_rows
                        if row['stream_name'] == stream_name
                        and row['event_role'] in required_roles}
                    if set(mapping) != required_roles:
                        continue
                    datasets = {
                        dataset_name
                        for dataset_name, stream, _ in available
                        if stream == stream_name}
                    matches = [
                        dataset_name for dataset_name in datasets
                        if all(
                            (dataset_name, stream_name, event_name) in available
                            for event_name in mapping.values())]
                    if len(matches) > 1:
                        raise ValueError(
                            'Multiple ephys datasets contain the required '
                            f'events for {subject_name} {session_name}.')
                    if len(matches) == 1:
                        source_keys = {
                            role: {
                                **restriction,
                                'dataset_name': matches[0],
                                'stream_name': stream_name,
                                'event_name': event_name}
                            for role, event_name in mapping.items()}
                        break
                if source_keys is None:
                    raise ValueError(
                        'No complete NIDAQ event set found for '
                        f'{subject_name} {session_name}.')

                event_rows = list(
                    (DatasetEvents.Digital() & list(source_keys.values()))
                    .fetch_synced())
                event_rows = {
                    (row['dataset_name'], row['stream_name'], row['event_name']): row
                    for row in event_rows}
                aligned = {}
                for role, source_key in source_keys.items():
                    row = event_rows[(
                        source_key['dataset_name'], source_key['stream_name'],
                        source_key['event_name'])]
                    timestamps = np.asarray(row['event_timestamps'], dtype=float)
                    values = row.get('event_values')
                    values = None if values is None else np.asarray(values)
                    if values is not None and values.shape != timestamps.shape:
                        raise ValueError(
                            f'Event values do not match timestamps for {role}.')
                    if role == 'visual_stim':
                        aligned['stim'] = timestamps
                    elif role == 'trial_start':
                        aligned[role] = (
                            timestamps[::2] if values is None
                            else timestamps[values == 1])
                    else:
                        aligned[role] = (
                            timestamps if values is None
                            else timestamps[values == 1])
                        aligned[f'{role}_exit'] = (
                            np.array([]) if values is None
                            else timestamps[values == 0])

                stim = np.sort(aligned['stim'])
                if stim.size:
                    bursts = np.split(
                        stim, np.where(np.diff(stim) > 0.020)[0] + 1)
                    stim = np.asarray([burst[0] for burst in bursts])
                trial_starts = np.asarray(aligned['trial_start'], dtype=float)
                center_exits = np.asarray(
                    aligned['center_port_exit'], dtype=float)
                left_entries = np.asarray(aligned['left_port'], dtype=float)
                right_entries = np.asarray(aligned['right_port'], dtype=float)
                if trial_starts.size == 0 or center_exits.size == 0:
                    raise ValueError(
                        'NIDAQ trial starts or center-port exits are unavailable '
                        f'for {subject_name} {session_name}.')

                sync_rows = [
                    row for row in session_rows
                    if int(row['trial_num']) < trial_starts.size
                    and row['t_sync'] is not None
                    and np.isfinite(row['t_sync'])]
                if len(sync_rows) < 2:
                    raise ValueError(
                        'Insufficient Bpod/NIDAQ sync points for '
                        f'{subject_name} {session_name}.')
                bpod_sync = np.asarray(
                    [row['t_sync'] for row in sync_rows], dtype=float)
                nidq_sync = np.asarray([
                    trial_starts[int(row['trial_num'])] for row in sync_rows
                ], dtype=float)
                order = np.argsort(bpod_sync)
                bpod_sync = bpod_sync[order]
                nidq_sync = nidq_sync[order]

                for row in session_rows:
                    if (row['response'] not in (-1, 1)
                            or row['t_sync'] is None
                            or not np.isfinite(row['t_sync'])
                            or row['t_react'] is None
                            or not np.isfinite(row['t_react'])):
                        continue
                    bpod_stims = np.asarray(row['stim_events'], dtype=float)
                    bpod_stims = bpod_stims[np.isfinite(bpod_stims)]
                    trial_num = int(row['trial_num'])
                    if bpod_stims.size == 0 or trial_num >= trial_starts.size:
                        continue
                    trial_start = trial_starts[trial_num]
                    trial_end = (
                        trial_starts[trial_num + 1]
                        if trial_num + 1 < trial_starts.size else np.inf)
                    first_stim_target = float(np.interp(
                        float(row['t_sync']) + float(bpod_stims[0]),
                        bpod_sync, nidq_sync))
                    center_exit_target = float(np.interp(
                        float(row['t_react']), bpod_sync, nidq_sync))
                    candidates = center_exits[
                        (center_exits > trial_start)
                        & (center_exits < trial_end)]
                    if candidates.size == 0:
                        continue
                    center_exit = float(candidates[
                        np.argmin(np.abs(candidates - center_exit_target))])
                    if abs(center_exit - center_exit_target) > 0.1:
                        continue

                    observation_end = center_exit
                    if observation_window == 'response':
                        if (row['t_response'] is None
                                or not np.isfinite(row['t_response'])):
                            continue
                        response_target = float(np.interp(
                            float(row['t_response']), bpod_sync, nidq_sync))
                        response_entries = (
                            right_entries if row['response'] == 1
                            else left_entries)
                        candidates = response_entries[
                            (response_entries > center_exit)
                            & (response_entries < trial_end)]
                        if candidates.size == 0:
                            continue
                        observation_end = float(candidates[
                            np.argmin(np.abs(candidates - response_target))])
                        if abs(observation_end - response_target) > 0.1:
                            continue

                    trial_stims = stim[
                        (stim >= trial_start) & (stim < observation_end)
                        & (stim < trial_end)]
                    if trial_stims.size == 0:
                        continue
                    first_stim = float(trial_stims[
                        np.argmin(np.abs(trial_stims - first_stim_target))])
                    if abs(first_stim - first_stim_target) > 0.1:
                        continue
                    trial_stims = trial_stims[trial_stims >= first_stim]
                    rate = row['stim_rate_vision']
                    if rate is None or not np.isfinite(rate):
                        continue
                    trials.append({
                        'subject_name': row['subject_name'],
                        'session_name': row['session_name'],
                        'dataset_name': row['dataset_name'],
                        'trial_num': trial_num,
                        'stim_times': trial_stims,
                        'first_stim_time': first_stim,
                        'observation_end_time': observation_end,
                        'response': int(row['response']),
                        'stim_rate': float(rate),
                        'event_stream': stream_name,
                    })
        else:
            end_field = (
                't_react' if observation_window == 'center_exit'
                else 't_response')
            for row in rows:
                stims = np.asarray(row['stim_events'], dtype=float)
                stims = stims[np.isfinite(stims)]
                observation_end = row[end_field]
                trial_sync = row['t_sync']
                if (row['response'] not in (-1, 1) or stims.size == 0
                        or observation_end is None
                        or not np.isfinite(observation_end)
                        or trial_sync is None or not np.isfinite(trial_sync)):
                    continue
                observation_end = float(observation_end) - float(trial_sync)
                stims = stims[stims < observation_end]
                rate = row['stim_rate_vision']
                if (stims.size == 0 or observation_end <= stims[0]
                        or rate is None or not np.isfinite(rate)):
                    continue
                trials.append({
                    'subject_name': row['subject_name'],
                    'session_name': row['session_name'],
                    'dataset_name': row['dataset_name'],
                    'trial_num': int(row['trial_num']),
                    'stim_times': stims,
                    'first_stim_time': float(stims[0]),
                    'observation_end_time': observation_end,
                    'response': int(row['response']),
                    'stim_rate': float(rate),
                    'event_stream': 'bpod',
                })

        return trials

    @classmethod
    def fit_psychophysical_kernel(cls, is_nidq=False,
                                  observation_window='center_exit', **key):
        """Fit a visual psychophysical kernel without storing derived data."""
        from sklearn.linear_model import LogisticRegression
        from sklearn.model_selection import StratifiedKFold

        trials = cls.trial_events(
            is_nidq=is_nidq,
            observation_window=observation_window,
            **key,
        )
        timebins = 10
        bin_width_s = 0.1
        bin_edges = np.arange(timebins + 1, dtype=float) * bin_width_s
        bin_centers_s = (bin_edges[:-1] + bin_edges[1:]) / 2
        residual = np.full(
            (len(trials), timebins), np.nan, dtype=float)
        expected_counts = np.full_like(residual, np.nan)
        for trial_index, trial in enumerate(trials):
            stims = trial['stim_times']
            first_stim = trial['first_stim_time']
            observation_end = trial['observation_end_time']
            rate = trial['stim_rate']
            duration = float(observation_end - first_stim)
            relative_stims = np.asarray(stims, dtype=float) - first_stim
            relative_stims = relative_stims[
                (relative_stims >= 0) & (relative_stims < duration)]
            for bin_index in range(timebins):
                bin_start = bin_edges[bin_index]
                if bin_start >= duration:
                    continue
                observed_end = min(bin_edges[bin_index + 1], duration)
                observed_duration = observed_end - bin_start
                count = np.sum(
                    (relative_stims >= bin_start)
                    & (relative_stims < observed_end))
                expected = rate * observed_duration
                residual[trial_index, bin_index] = count - expected
                expected_counts[trial_index, bin_index] = expected

        choices = (
            np.asarray([trial['response'] for trial in trials], dtype=int) == 1
        ).astype(int)
        n_observed = np.sum(np.isfinite(residual), axis=0).astype(int)
        if (residual.size == 0 or np.unique(choices).size < 2):
            return None

        n_bins_fit = 0
        for bin_index in range(timebins):
            complete = np.all(
                np.isfinite(residual[:, :bin_index + 1]), axis=1)
            if (n_observed[bin_index] < 50 or np.sum(complete) < 50):
                break
            n_bins_fit = bin_index + 1
        if n_bins_fit == 0:
            return None

        complete = np.all(np.isfinite(residual[:, :n_bins_fit]), axis=1)
        complete_residual = residual[complete, :n_bins_fit]
        choices_fit = choices[complete]
        if complete_residual.shape[0] < 50 or np.unique(choices_fit).size < 2:
            return None
        n_splits = int(min(10, np.min(np.bincount(choices_fit))))
        if n_splits < 2:
            return None

        expected_fit = expected_counts[complete, :n_bins_fit]
        mean_rate = np.sum(expected_fit, axis=1)
        if n_bins_fit == 1:
            design = mean_rate[:, None]
            coefficient_to_weights = np.ones((1, 1))
        else:
            eye = np.eye(n_bins_fit)
            basis_source = np.column_stack([
                eye[:, index] - eye[:, -1]
                for index in range(n_bins_fit - 1)])
            basis = np.linalg.qr(basis_source, mode='reduced')[0]
            design = np.column_stack(
                (complete_residual @ basis, mean_rate))
            coefficient_to_weights = np.column_stack(
                (basis, np.ones(n_bins_fit)))

        weights = []
        errors = []
        scores = []
        biases = []
        splitter = StratifiedKFold(
            n_splits=n_splits, shuffle=True, random_state=0)
        for train_index, test_index in splitter.split(design, choices_fit):
            x_train, x_test = design[train_index], design[test_index]
            y_train, y_test = (
                choices_fit[train_index], choices_fit[test_index])
            model = LogisticRegression(
                solver='liblinear', C=1.0, fit_intercept=True
            ).fit(x_train, y_train)
            predict_prob = model.predict_proba(x_train)
            variance = np.prod(predict_prob, axis=1)
            covariance = np.linalg.pinv(
                np.dot(x_train.T * variance, x_train))
            weight_full = np.full(timebins, np.nan)
            error_full = np.full(timebins, np.nan)
            weight_full[:n_bins_fit] = (
                coefficient_to_weights @ model.coef_[0])
            weight_covariance = (
                coefficient_to_weights @ covariance
                @ coefficient_to_weights.T)
            error_full[:n_bins_fit] = np.sqrt(
                np.diag(weight_covariance))
            weights.append(weight_full)
            errors.append(error_full)
            scores.append(model.score(x_test, y_test))
            biases.append(float(model.intercept_[0]))

        weights = np.asarray(weights)
        errors = np.asarray(errors)
        scores = np.asarray(scores)
        weights_mean = np.full(timebins, np.nan)
        weights_error = np.full(timebins, np.nan)
        weights_mean[:n_bins_fit] = np.mean(
            weights[:, :n_bins_fit], axis=0)
        weights_error[:n_bins_fit] = np.mean(
            errors[:, :n_bins_fit], axis=0)
        score_mean = float(np.mean(scores))
        majority_accuracy = float(
            max(np.mean(choices_fit), 1 - np.mean(choices_fit)))
        return {
            'timing_source': 'nidq' if is_nidq else 'bpod',
            'observation_window': observation_window,
            'bin_centers_s': bin_centers_s,
            'weights': weights,
            'weights_mean': weights_mean,
            'weights_error': weights_error,
            'scores': scores,
            'score_mean': score_mean,
            'majority_accuracy': majority_accuracy,
            'score_above_majority': score_mean - majority_accuracy,
            'bias': np.asarray(biases),
            'bias_mean': float(np.mean(biases)),
            'n_observed_per_bin': n_observed,
            'n_trials_fit': int(complete_residual.shape[0]),
            'n_bins_fit': int(n_bins_fit),
        }
