"""Parser output for synthetic sessions; no labdata imports or database."""
from pathlib import Path
import re
import tempfile
import unittest
import warnings

import numpy as np
from scipy.io import savemat

from helpers import ROOT, definition, example_session, parse, parser_namespace, session_data


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


class StimulusTrainTest(unittest.TestCase):
    parse = staticmethod(parse)

    def test_channels_repeat_the_shared_padded_waveform(self):
        trains, duration = parser_namespace()['_stimulus_trains'](
            [[0., .01, .01], [0., .03, .01]], .01, .07)
        self.assertAlmostEqual(duration, .13)
        np.testing.assert_allclose(trains[0], [0., .02, .06, .08, .12])
        np.testing.assert_allclose(trains[1], [0., .04, .06, .10, .12])

    def test_subsample_rounding_and_truncated_last_repeat(self):
        fs = 192000
        trains, duration = parser_namespace()['_stimulus_trains'](
            [[.49/fs, .51/fs, 1/fs]], 2/fs, 1.51/fs)
        np.testing.assert_array_equal(trains[0]*fs, [0., 3., 6.])
        self.assertEqual(duration*fs, 8.)

    def test_invalid_stimulus_inputs_fail_instead_of_inventing_events(self):
        fn=parser_namespace()['_stimulus_trains']
        for isi,pulse,extra in [([0,np.nan],.01,0),([0,-1],.01,0),
                                ([0,.01],0.,0),([0,.01],.01,-1)]:
            with self.subTest(isi=isi,pulse=pulse,extra=extra):
                with self.assertRaises(ValueError): fn([isi],pulse,extra)

    def test_synchronous_channels_share_one_event_list(self):
        data=session_data()
        data['Modality'][:]=3
        for t in range(3): data['InterStimulusIntervalList'][t,1]=data['InterStimulusIntervalList'][t,0]
        (_,params,_),_=self.parse(data)
        self.assertTrue(all('stim_events_audio' not in p for p in params))
        np.testing.assert_allclose(params[0]['stim_events'],[.2,.415,.63,.845])


class DidNotChooseTest(unittest.TestCase):
    def process(self, frame, assembler="DemonstratorTaskSMA"):
        ns = parser_namespace()
        session = example_session()[1]
        settings = session['SettingsFile'].tolist()
        identified = np.empty((), dtype=settings.dtype.descr + [('smaAssembler', object)])
        for name in settings.dtype.names:
            identified[name] = settings[name]
        identified['smaAssembler'] = assembler
        session['SettingsFile'][()] = identified
        ns['load_chipmunk_trialdata'] = lambda _: (frame, session, {'weight': np.nan})
        return ns['process_chipmunk_file']('unused')[0][0][0]

    def test_no_choice_clips_the_stimulus_but_not_the_response(self):
        frame = example_session()[0]
        frame['Reward'] = [np.array([np.nan, np.nan])]
        frame['DemonDidNotChoose'] = [np.array([.5, .51])]
        trial = self.process(frame)
        self.assertAlmostEqual(trial['stim_duration'], .3)  # PlayStimulus at .2, DidNotChoose at .5
        self.assertIsNone(trial['t_response'])
        self.assertEqual((trial['with_choice'], trial['rewarded']), (0, 0))

    def test_paced_task_does_not_stop_the_stimulus_on_no_choice(self):
        # DemonstratorPaced*SMA send SoftCode 255 on reward and wrong choice, not on DemonDidNotChoose.
        frame, session, meta = example_session()
        frame['Reward'] = [np.array([np.nan, np.nan])]
        frame['DemonDidNotChoose'] = [np.array([.5, .51])]
        paced = np.empty((), dtype=session.dtype.descr + [('PacedFlag', float)])
        for name in session.dtype.names:
            paced[name][()] = session[name][()]
        for flag, expected in [(1., 1.5), (0., 1.5)]:
            paced['PacedFlag'] = flag
            ns = parser_namespace()
            ns['load_chipmunk_trialdata'] = lambda _: (frame, paced, meta)
            self.assertAlmostEqual(ns['process_chipmunk_file']('unused')[0][0][0]['stim_duration'], expected)

    def test_trial_without_no_choice_keeps_the_full_train(self):
        frame = example_session()[0]
        frame['Reward'] = [np.array([np.nan, np.nan])]
        frame['DemonDidNotChoose'] = [np.array([np.nan, np.nan])]
        self.assertAlmostEqual(self.process(frame)['stim_duration'], 1.5)  # 1 s + ExtraStimulusDuration

    def test_state_matrices_that_stop_the_stimulus_on_no_choice(self):
        frame = example_session()[0]
        frame['Reward'] = [np.array([np.nan, np.nan])]
        frame['DemonDidNotChoose'] = [np.array([.5, .51])]
        root = ROOT.parent
        paths = list((root / 'chipmunk/Functions/StateMatrices').glob('*.m')) + list((root / 'chipmunk_solo/Functions/StateMatrices').glob('*.m'))
        stopping = []
        for path in paths:
            block = re.search(r"'Name', 'DemonDidNotChoose'.*?'OutputActions', (.*?);", path.read_text(), re.S)
            if block and re.search(r"'SoftCode',\s*255", block[1]):
                stopping.append(path.stem)
                with self.subTest(producer=path.stem):
                    self.assertAlmostEqual(self.process(frame, path.stem)['stim_duration'], .3)
        self.assertEqual(len(stopping), 9)
        for producer in ('DemonstratorSelfInitiatedTaskSMA', 'DemonstratorPacedTaskSMA',
                         'DemonstratorPacedFixationTrainingSMA', 'ObserverTaskSMA_outdated', None, 'UnknownLegacy'):
            with self.subTest(producer=producer):
                self.assertAlmostEqual(self.process(frame, producer)['stim_duration'], 1.5)


def legacy_session(labels, as_cell=True, with_rate=False):
    """Early recording: string modality labels, no StimulusRate, per-modality event counts."""
    data = session_data()
    n = 3
    labels_array = np.empty(n, dtype=object)
    for i, label in enumerate(labels):
        labels_array[i] = label
    data['Modality'] = labels_array if as_cell else np.array(labels)
    if not with_rate:
        del data['StimulusRate']
    del data['InterStimulusIntervalList']
    data['nVisualEvents'] = np.array([4., 5., 6.])
    data['nAuditoryEvents'] = np.array([7., 8., 9.])
    for name in ('visualIsis', 'auditoryIsis'):
        isis = np.empty(n, dtype=object)
        for i in range(n):
            isis[i] = np.array([0., .2, .2, .2, .34])
        data[name] = isis
    return data


class LegacyModalityTest(unittest.TestCase):
    def load(self, data):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'FakeSubject_legacy.mat'
            savemat(path, {'SessionData': data}, long_field_names=True)
            return parser_namespace()['load_chipmunk_trialdata'](str(path))

    def test_string_labels_convert_without_mutating_the_saved_labels(self):
        labels = ['Visual', 'Auditory', 'Visual']
        frame, session, _ = self.load(legacy_session(labels))
        self.assertEqual(frame['stimulus_modality'].tolist(), ['visual', 'auditory', 'visual'])
        self.assertEqual(session['Modality'].tolist().tolist(), labels)
        # The rate fallback reads the saved labels: counts only where the modality matches.
        np.testing.assert_array_equal(frame['stimulus_rate_visual'].values, [4., np.nan, 6.])
        np.testing.assert_array_equal(frame['stimulus_rate_auditory'].values, [np.nan, 8., np.nan])

    def test_every_accepted_label_maps_to_its_code(self):
        codes = parser_namespace()['_modality_codes']
        for label, code in [('visual', 1), ('Visual', 1), ('audio', 2), ('auditory', 2), ('Auditory', 2),
                            ('audio+visual', 3), ('multi-sensory', 3), ('Multi-sensory', 3)]:
            for container in (np.array([label]), np.array([label], dtype=object), [label]):
                self.assertEqual(codes(container).tolist(), [code], (label, type(container)))
        self.assertEqual(codes(np.array([1., 2., 3.])).tolist(), [1, 2, 3])  # MATLAB doubles
        self.assertEqual(codes(2).tolist(), [2])

    def test_unknown_label_in_a_file_names_the_value(self):
        with self.assertRaisesRegex(ValueError, "Unknown stimulus modality 'Olfactory'"):
            self.load(legacy_session(['Visual', 'Olfactory', 'Visual']))

    def test_numeric_codes_still_load(self):
        data = legacy_session(['Visual'] * 3, with_rate=True)
        data['Modality'] = np.array([1, 2, 3])
        frame, _, _ = self.load(data)
        self.assertEqual(frame['stimulus_modality'].tolist(), ['visual', 'auditory', 'audio+visual'])

    def test_padded_matlab_labels_preserve_rates(self):
        frame, _, _ = self.load(legacy_session(['Visual  ', 'Auditory', 'Visual  '], as_cell=False))
        self.assertEqual(frame['stimulus_modality'].tolist(), ['visual', 'auditory', 'visual'])
        np.testing.assert_array_equal(frame['stimulus_rate_visual'], [4., np.nan, 6.])
        np.testing.assert_array_equal(frame['stimulus_rate_auditory'], [np.nan, 8., np.nan])


class RewardAndOutcomeTest(unittest.TestCase):
    def data(self, assembler='MultipleModalitiesTaskSMA', n=3):
        data = session_data(n=n)
        if assembler is not None:
            data['SettingsFile']['smaAssembler'] = assembler
            old = data['TrialSettings']
            settings = np.empty(old.shape, dtype=old.dtype.descr + [('smaAssembler', object)])
            for name in old.dtype.names:
                settings[name] = old[name]
            settings['smaAssembler'] = assembler
            data['TrialSettings'] = settings
        return data

    def test_passive_identity_and_zero_choice_task(self):
        for assembler, mode in [('PassiveVisualStimSMA', 'passive'),
                                ('MultipleModalitiesTaskSMA', 'detection')]:
            data = self.data(assembler)
            for raw in data['RawEvents']['Trial'][0]:
                raw['States']['DemonReward'] = [np.nan, np.nan]
                raw['States']['DemonWaitForResponse'] = [np.nan, np.nan]
            (trials, params, settings), _ = parse(data)
            self.assertEqual(settings['setting_task_mode'], mode)
            self.assertEqual([p['configured_reward_volume'] for p in params],
                             [None if mode == 'passive' else 3.] * 3)
            self.assertEqual([t['with_choice'] for t in trials], [0] * 3)

    def test_observer_reward_is_not_a_task_reward_or_response(self):
        data = self.data()
        for raw in data['RawEvents']['Trial'][0]:
            states = raw['States']
            states['DemonReward'] = [np.nan, np.nan]
            states['DemonWrongChoice'] = [np.nan, np.nan]
            raw['States'] = dict(ObsReward=[.4, .5], **states)
        (trials, _, _), _ = parse(data)
        self.assertEqual([t['rewarded'] for t in trials], [0] * 3)
        self.assertTrue(all(t['t_response'] is None for t in trials))

    def test_task_reward_is_found_after_unvisited_observer_reward(self):
        data = self.data()
        for raw in data['RawEvents']['Trial'][0]:
            raw['States'] = dict(ObsReward=[np.nan, np.nan], **raw['States'])
        (trials, _, _), _ = parse(data)
        self.assertEqual([t['rewarded'] for t in trials], [1] * 3)
        self.assertTrue(all(t['t_response'] is not None for t in trials))

    def test_bare_reward_after_observer_state_is_counted(self):
        data = self.data()
        for raw in data['RawEvents']['Trial'][0]:
            states = dict(raw['States'])
            states['Reward'] = states.pop('DemonReward')
            states['WrongChoice'] = states.pop('DemonWrongChoice')
            states['ObsReward'] = [np.nan, np.nan]
            raw['States'] = states
        (trials, _, _), _ = parse(data)
        self.assertEqual([t['rewarded'] for t in trials], [1] * 3)

    def test_unknown_reward_state_and_unknown_passive_fail(self):
        data = self.data()
        for raw in data['RawEvents']['Trial'][0]:
            raw['States']['DemonRewardDelivery'] = raw['States'].pop('DemonReward')
        with self.assertRaisesRegex(ValueError, 'Unrecognized reward states'):
            parse(data)
        data = self.data(assembler='ForkPassiveStimSMA')
        for raw in data['RawEvents']['Trial'][0]:
            for name in ('DemonReward', 'DemonWrongChoice', 'Reward', 'WrongChoice'):
                raw['States'].pop(name, None)
        with self.assertRaisesRegex(ValueError, 'No defined task outcome states'):
            parse(data)

    def test_missing_trial_zero_volume_fails_before_database(self):
        for volume in (np.nan, np.array([])):
            data = self.data()
            data['TrialSettings']['leftRewardVolume'][0, 0] = volume
            with self.assertRaisesRegex(ValueError, 'Unknown trial-zero reward volume'):
                parse(data)

    def test_legacy_task_inference(self):
        (_, params, settings), _ = parse(self.data(None))
        self.assertEqual(settings['setting_task_mode'], 'detection')
        self.assertEqual(params[0]['configured_reward_volume'], 3.)

    def test_inconsistent_assembler_rejected(self):
        for index in range(3):
            data = self.data()
            data['TrialSettings']['smaAssembler'][0, index] = 'PassiveVisualStimSMA'
            with self.assertRaisesRegex(ValueError, 'Inconsistent per-trial smaAssembler'):
                parse(data)

    def test_correct_side_snapshot_and_revised_choice(self):
        data = self.data()
        data['CorrectSide'] = [0, 1, 0]
        data['ResponseSide'] = [1, 0, 1]  # first poke can differ from the rewarded valve
        for field, values in [('leftRewardVolume', [2., 2., 4.]),
                              ('rightRewardVolume', [6., 6., 6.])]:
            for index, value in enumerate(values):
                data['TrialSettings'][field][0, index] = value
        (trials, params, settings), _ = parse(data)
        self.assertEqual([p['rewarded_position'] for p in params], ['left', 'right', 'left'])
        self.assertEqual([p['configured_reward_volume'] for p in params], [2., 6., 4.])
        self.assertEqual([t['response'] for t in trials], [1, -1, 1])
        self.assertEqual(settings['setting_left_reward_volume'], 2.)

    def test_squeezed_single_trial(self):
        (_, params, _), _ = parse(self.data(n=1))
        self.assertEqual(params[0]['configured_reward_volume'], 3.)
        self.assertIsInstance(params[0]['configured_reward_volume'], float)

    def test_empty_and_nan_remain_unknown(self):
        for value in (np.array([]), np.nan):
            data = self.data()
            data['TrialSettings']['leftRewardVolume'][0, 1] = value
            (_, params, _), _ = parse(data)
            self.assertEqual([p['configured_reward_volume'] for p in params], [3., None, 3.])

    def test_invalid_volumes_fail_instead_of_using_trial_zero(self):
        for value in (-1., np.inf, -np.inf, 'bad', '2', [2., 4.]):
            data = self.data()
            data['TrialSettings']['leftRewardVolume'][0, 1] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'configured reward volume'):
                parse(data)


if __name__ == '__main__':
    unittest.main()
