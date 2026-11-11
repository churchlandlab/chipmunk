"""Check parser output against proposed definitions without a database or MAT file."""
import ast
from pathlib import Path
import unittest
import warnings

import numpy as np
import pandas as pd
from scipy.interpolate import interp1d

ROOT = Path(__file__).resolve().parents[1] / 'labdata_plugin'


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


class ParserFieldsTest(unittest.TestCase):
    def test_outputs_fit_definitions_without_losing_stimulus_values(self):
        namespace = parser_namespace()
        namespace['load_chipmunk_trialdata'] = lambda _: example_session()
        (trials, parameters, settings), _ = namespace['process_chipmunk_file']('unused')
        for name, rows in [('Trial', trials), ('TrialParameters', parameters),
                           ('Chipmunk', [settings])]:
            allowed = {line.split(':')[0].split('=')[0].strip()
                       for line in definition(name).splitlines() if ':' in line}
            allowed.add('trial_num')
            for row in rows:
                self.assertEqual(set(row) - allowed, set(), name)
        self.assertEqual(parameters[0]['stim_event_duration'], .03)
        self.assertEqual(parameters[0]['stim_brightness'], .5)
        self.assertEqual(parameters[0]['stim_loudness'], .7)
        self.assertEqual(parameters[0]['required_wait_time'], .8)
        np.testing.assert_array_equal(parameters[0]['stim_events'], [.2, .4])
        self.assertEqual(trials[0]['response'], 1)

    def test_required_wait_time_is_nullable_seconds(self):
        line = next(line for line in definition('TrialParameters').splitlines()
                    if line.strip().startswith('required_wait_time'))
        self.assertIn('= NULL', line)
        self.assertEqual(line.split(':')[1].split('#')[0].strip(), 'double')


if __name__ == '__main__':
    unittest.main()
