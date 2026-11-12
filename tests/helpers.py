"""Shared fixtures: the parser loaded without labdata, and synthetic sessions."""
import ast
from pathlib import Path
import tempfile
import warnings

import numpy as np
import pandas as pd
from scipy.interpolate import interp1d
from scipy.io import savemat

ROOT = Path(__file__).resolve().parents[1] / 'labdata_plugin'
NAMES = np.array(['Sync', 'InterTrialInterval', 'PlayStimulus', 'StopStimulus', 'FinishTrial'], dtype=object)


def parser_namespace():
    source = ast.parse((ROOT / 'utils.py').read_text())
    tree = ast.Module(body=[n for n in source.body
                           if isinstance(n, ast.FunctionDef)],
                      type_ignores=[])
    # labdata's extrapolate_time_from_clock
    clock = lambda master_clock, master_events, slave_events: interp1d(
        master_events, master_clock, fill_value='extrapolate')(slave_events)
    namespace = {'np': np, 'pd': pd, 'warnings': warnings, 'extrapolate_time_from_clock': clock}
    exec(compile(tree, str(ROOT / 'utils.py'), 'exec'), namespace)
    return namespace


def definition(name):
    for node in ast.walk(ast.parse((ROOT / 'pluginschema.py').read_text())):
        if isinstance(node, ast.ClassDef) and node.name == name:
            for item in node.body:
                if isinstance(item, ast.Assign) and any(
                        isinstance(t, ast.Name) and t.id == 'definition'
                        for t in item.targets):
                    return item.value.value
    raise AssertionError(name)


def example_session():
    settings = np.array(('R', 0., 1.), dtype=[('highRateSide', 'U1'),
                        ('propOnlyAuditory', float), ('propOnlyVisual', float)])
    trial_settings = np.array([(3., 3.)], dtype=[('leftRewardVolume', float),
                                               ('rightRewardVolume', float)])
    session = np.empty((), dtype=[('SettingsFile', object), ('TrialSettings', object)])
    session['SettingsFile'][()] = settings
    session['TrialSettings'][()] = trial_settings
    row = dict(trial_start_time=0., response_side=1, correct_side=1,
               stimulus_modality='visual', stimulus_rate_auditory=np.nan,
               stimulus_rate_visual=8., category_boundary=12.,
               stimulus_event_timestamps=np.array([.2, .4]),
               stimulus_event_duration=.03, stimulus_brightness=.5,
               stimulus_loudness=.7, min_isi=.025, is_poisson=1,
               ExtraStimulusDuration=.5, proportion_left=.5,
               anti_bias_strength=.2, anti_bias_tau=10.,
               pre_stim_delay_min=.1, pre_stim_delay_max=.2,
               pre_stim_delay_lambda=1., pre_stim_delay=.15,
               required_wait_time=.8, incorrect_choice_timeout=2.,
               early_withdrawal_timeout=1.)
    for state, start in [('WaitForCenterFixation', 0.), ('Sync', .05),
                         ('InitFixation', .1), ('PlayStimulus', .2),
                         ('WaitForWithdrawalFromCenter', .5),
                         ('WaitForResponse', .6), ('Reward', .7),
                         ('FinishTrial', 1.), ('response_port_out', 1.2)]:
        row[state] = np.array([start, start + .01])
    for port in ('Port1', 'Port2', 'Port3'):
        row[port + 'In'] = np.array([.1])
        row[port + 'Out'] = np.array([.2])
    return pd.DataFrame([row]), session, {'weight': np.nan}


def records(values, n):
    result = np.empty((1, n), dtype=[(key, object) for key in values])
    for key, value in values.items():
        for index in range(n):
            result[key][0, index] = value
    return result


def session_data(port_mode='missing_out', n=3, **gap_fields):
    settings = dict(leftRewardVolume=3., rightRewardVolume=3., stimBrightness=100.,
                    stimLoudness=50., propLeft=.5, antiBiasStrength=.2,
                    antiBiasTau=10., preStimDelayMin=.1, preStimDelayMax=.2,
                    preStimDelayLambda=1., wrongPunishTimeout=2.,
                    earlyPunishTimeout=1., isPoissonStim=1)
    trials = np.empty((1, n), dtype=object)
    intervals = np.empty((n, 2), dtype=object)
    for i in range(n):
        events = {'BNC1High': np.array([.05])}
        for port in range(1, 4):
            events[f'Port{port}In'] = np.array([.1]) if port_mode != 'empty' else np.array([])
            if port_mode == 'empty':
                events[f'Port{port}Out'] = np.array([])
            elif port_mode == 'present':
                events[f'Port{port}Out'] = np.array([.95])
        states = {name: np.array([t, t + .01]) for name, t in [
            ('DemonWaitForCenterFixation', 0.), ('Sync', .05),
            ('DemonInitFixation', .1), ('PlayStimulus', .2),
            ('DemonWaitForWithdrawalFromCenter', .5),
            ('DemonWaitForResponse', .6), ('DemonReward', .8),
            ('FinishTrial', 1.)]}
        states['DemonWrongChoice'] = np.array([np.nan, np.nan])
        trials[0, i] = dict(Events=events, States=states)
        intervals[i, 0] = np.array([0., .2, .2, .2, .34])
        intervals[i, 1] = np.array([np.nan])
    return dict(nTrials=n, RawEvents={'Trial': trials},
                SettingsFile=dict(highRateSide='R', propOnlyAuditory=0., propOnlyVisual=1.),
                TrialSettings=records(settings, n), ResponseSide=np.zeros(n),
                CorrectSide=np.zeros(n), Modality=np.ones(n, dtype=int), CategoryBoundary=12.,
                StimulusRate=np.array([[4., np.nan]] * n), StimulusDuration=np.full(n, .015),
                InterStimulusIntervalList=intervals, OutcomeRecord=np.ones(n),
                TrialDelays=records(dict(ExtraStimulusDuration=0.), n),
                ActualWaitTime=np.full(n, .7), SetWaitTime=np.full(n, .8),
                PreStimDelay=np.full(n, .15), TrialStartTimestamp=np.arange(n) * 2.,
                ReviseChoiceFlag=0, PacedFlag=0, **gap_fields)


def replay_data(statuses, status, events=None, stopped_after=None):
    """Active session of three trials plus a replay of the first len(statuses) of them."""
    data = session_data()
    count = len(statuses)
    raw = np.empty((1, count), dtype=object)
    for i in range(count):
        raw[0, i] = (dict(TrialStartTimestamp=100. + 2 * i, States=np.arange(1, 6),
                          StateTimestamps=[0., .1, .2, 1.2, 1.25, 1.26])
                     if statuses[i] == 'completed' else np.array([]))
    data['PassiveReplay'] = dict(
        sourceTrialNumbers=np.arange(1, count + 1), nRequested=count,
        nCompleted=statuses.count('completed'), status=status,
        trialStatus=np.array(statuses, dtype=object), rawEvents=raw, stateNames=NAMES,
        stoppedPulseAfter=np.array([]) if stopped_after is None else stopped_after)
    return data


def parse(data):
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'FakeSubject_contract.mat'
        savemat(path, {'SessionData': data}, long_field_names=True)
        return parser_namespace()['process_chipmunk_file'](str(path))
