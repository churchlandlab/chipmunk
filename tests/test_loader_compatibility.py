"""Exercise MATLAB serialization and the real loader without database imports."""
from pathlib import Path
import tempfile
import unittest
import warnings

import numpy as np
from scipy.io import savemat

from test_parser_fields import parser_namespace


def records(values, n):
    result = np.empty((1, n), dtype=[(key, object) for key in values])
    for key, value in values.items():
        for index in range(n):
            result[key][0, index] = value
    return result


def session_data(port_mode='missing_out', **gap_fields):
    n = 3
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


class LoaderCompatibilityTest(unittest.TestCase):
    def parse(self, **kwargs):
        namespace = parser_namespace()
        namespace['warnings'] = warnings
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'FakeSubject_fixture.mat'
            savemat(path, {'SessionData': session_data(**kwargs)}, long_field_names=True)
            frame, _, _ = namespace['load_chipmunk_trialdata'](str(path))
            self.assertIsNotNone(frame)
            (trials, parameters, _), _ = namespace['process_chipmunk_file'](str(path))
        self.assertEqual(len(trials), 3)
        return trials, parameters

    def test_missing_port_exits_do_not_create_events(self):
        trials, _ = self.parse()
        for trial in trials:
            np.testing.assert_array_equal(trial['left_poke'][:, 1], [1.])

    def test_explicitly_empty_port_arrays_are_absent(self):
        trials, _ = self.parse(port_mode='empty')
        for trial in trials:
            for name in ('left_poke', 'center_poke', 'right_poke'):
                self.assertIsNone(trial[name])

    def test_effective_solo_gap_takes_precedence(self):
        _, parameters = self.parse(port_mode='present', MinInterval=[.025, .125, .05],
                                   minimumInterStimulusInterval=[.07] * 3)
        np.testing.assert_array_equal([p['min_isi'] for p in parameters], [.025, .125, .05])

    def test_legacy_gap_aliases(self):
        for field in ('minimumInterStimulusInterval', 'minInterStimulusInterval'):
            with self.subTest(field=field):
                _, parameters = self.parse(port_mode='present', **{field: [.03, .04, .05]})
                np.testing.assert_array_equal([p['min_isi'] for p in parameters], [.03, .04, .05])

    def test_legacy_missing_gap_keeps_existing_default(self):
        _, parameters = self.parse(port_mode='present')
        np.testing.assert_array_equal([p['min_isi'] for p in parameters], [.025] * 3)

    def test_scalar_gap_applies_to_all_trials(self):
        _, parameters = self.parse(port_mode='present', MinInterval=.05)
        np.testing.assert_array_equal([p['min_isi'] for p in parameters], [.05] * 3)


if __name__ == '__main__':
    unittest.main()
