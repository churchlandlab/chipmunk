"""Regression cases for the Chipmunk parser fixes, without LabData imports or a database.

Everything is synthetic: temporary MAT files written with SciPy, GPIO traces built in
memory, and in-memory table doubles. No local camlog holds a Bpod sync train yet, so the
camera cases check the pairing logic, not a recorded rig.
"""
import ast
from pathlib import Path
import tempfile
import unittest
import warnings

import numpy as np
import pandas as pd
from scipy.io import savemat

from test_loader_compatibility import session_data
from test_parser_fields import ROOT, example_session, parser_namespace

NAMES = np.array(['Sync', 'InterTrialInterval', 'PlayStimulus', 'StopStimulus', 'FinishTrial'], dtype=object)


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


class AbortedReplayTest(unittest.TestCase):
    def test_eventless_aborted_and_unstarted_attempts_are_tolerated(self):
        data = replay_data(['completed', 'aborted', 'not_started'], 'aborted', stopped_after=1)
        _, metadata = parse(data)
        self.assertEqual([r['passive_trial_num'] for r in metadata['passive_trials']], [0])

    def test_eventless_failed_attempt_still_raises(self):
        for statuses, status in [(['failed', 'not_started', 'not_started'], 'failed'),
                                 (['completed', 'failed', 'not_started'], 'failed')]:
            with self.subTest(statuses=statuses):
                with self.assertRaisesRegex(ValueError, 'no recorded event timestamps'):
                    parse(replay_data(statuses, status))

    def test_eventless_completed_attempt_still_raises(self):
        data = replay_data(['completed', 'completed', 'not_started'], 'completed')
        data['PassiveReplay']['rawEvents'][0, 1] = np.array([])
        with self.assertRaisesRegex(ValueError, 'no recorded event timestamps'):
            parse(data)

    def test_aborted_attempt_in_a_session_that_did_not_abort_raises(self):
        with self.assertRaisesRegex(ValueError, 'no recorded event timestamps'):
            parse(replay_data(['completed', 'aborted', 'not_started'], 'completed'))


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

    def test_input_is_never_modified(self):
        labels = np.array(['Visual', 'Auditory'], dtype=object)
        parser_namespace()['_modality_codes'](labels)
        self.assertEqual(labels.tolist(), ['Visual', 'Auditory'])

    def test_unknown_values_fail_explicitly(self):
        codes = parser_namespace()['_modality_codes']
        for bad in (['Visual', 'Olfactory'], [0], [4], [1.5], [np.nan], [None], ['1']):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(ValueError, 'Unknown stimulus modality'):
                    codes(np.array(bad, dtype=object))

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

    def test_numeric_legacy_file_without_rate_keeps_its_nan_rates(self):
        # Unchanged behavior: the fallback has only ever matched the labels 'Visual' and 'Auditory'.
        data = legacy_session(['Visual'] * 3)
        data['Modality'] = np.array([1, 2, 1])
        frame, _, _ = self.load(data)
        self.assertTrue(frame['stimulus_rate_visual'].isna().all())


class Relation:
    """Minimal stand-in for a DataJoint relation."""
    def __init__(self, rows=(), primary_key=()):
        self.rows, self.primary_key = list(rows), primary_key

    def __and__(self, other):
        return self

    def __mul__(self, other):
        return self

    def __bool__(self):
        return bool(self.rows)

    def fetch(self, *args, **kwargs):
        return [self.rows[0][args[0]]] if args else self.rows

    def fetch1(self, *args):
        return self.rows[0]


def easy_performance(stim_rates, rewarded, boundary=12.):
    """performance_easy that chipmunk_insert_decision_task would store, using only doubles.

    Every trial has a choice; stim_int is stim_rate - boundary; rewarded is given per trial.
    """
    stim_rates, rewarded = list(stim_rates) * 3, list(rewarded) * 3  # TrialSet rows need more than 10 trials
    n = len(stim_rates)
    key = dict(subject_name='DEMO', session_name='DEMO', dataset_name='chipmunk')
    trial = pd.DataFrame(dict(
        trial_num=np.arange(n), rewarded_modality='visual', stim_rate_vision=np.asarray(stim_rates, float),
        stim_rate_audio=np.nan, category_boundary=boundary, with_choice=1,
        rewarded=np.asarray(rewarded, int), punished=1 - np.asarray(rewarded, int), response=1,
        initiated=1, early_withdrawal=0, t_response=1., t_gocue=.5, t_initiate=.2, t_start=0.,
        setting_left_reward_volume=3., setting_right_reward_volume=3.,
        setting_task_mode='detection', configured_reward_volume=3., rewarded_position='right'))
    for column, value in key.items():
        trial[column] = value
    chip = Relation(trial.to_dict('records'))
    chip.Trial = chip.TrialParameters = chip
    dataset = Relation([dict(key, session_datetime='2026-11-07 12:00:00')])
    decision = Relation()
    decision.TrialSet = Relation()
    writes = []
    tree = ast.parse((ROOT / 'utils.py').read_text())
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'chipmunk_insert_decision_task')
    # Drop the labdata imports so nothing can reach a database; the doubles are injected below.
    fn.body = [n for n in fn.body if not isinstance(n, (ast.ImportFrom, ast.Import))]
    env = dict(np=np, pd=pd, warnings=warnings, Chipmunk=chip, Dataset=dataset, Session=dataset,
               Watering=Relation(primary_key=('subject_name', 'watering_datetime')), DecisionTask=decision,
               _upsert_generated_row=lambda table, row: writes.append((table, row)),
               _configured_reward_volume=parser_namespace()['_configured_reward_volume'])
    exec(compile(ast.Module(body=[fn], type_ignores=[]), 'decision_task', 'exec'), env)
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        env['chipmunk_insert_decision_task'](key, mintrials=1)
    return next(float(row['performance_easy']) for table, row in writes if table is decision.TrialSet)


class EasyPerformanceTest(unittest.TestCase):
    """Easy trials are those at the largest |stim_rate - boundary|, whichever side it is on."""

    def test_symmetric_design_is_unchanged(self):
        # stim_int is +/-6 at the extremes, so signed and absolute maxima agree: 3 of 4 rewarded.
        self.assertEqual(easy_performance([6, 18, 6, 18, 9, 15], [1, 1, 1, 0, 0, 1]), .75)

    def test_larger_positive_extreme_is_unchanged(self):
        # stim_int +10 and -4: the signed maximum already was the absolute maximum.
        self.assertEqual(easy_performance([22, 22, 8, 8], [1, 0, 1, 1]), .5)

    def test_larger_negative_extreme_defines_easy(self):
        # stim_int -10 (3 of 4 rewarded) and +4 (0 of 2). The signed maximum selected the +4 trials.
        self.assertEqual(easy_performance([2, 2, 2, 2, 16, 16], [1, 1, 0, 1, 0, 0]), .75)

    def test_all_negative_design_is_scored(self):
        # stim_int -10, -6, -2: the signed maximum (-2) matched no |stim_int|, which scored 0.
        self.assertEqual(easy_performance([2, 2, 6, 6, 10, 10], [1, 0, 1, 1, 1, 1]), .5)


class CameraPulseTest(unittest.TestCase):
    """Default 100 Hz frames, camera and Bpod clocks identical, so a pulse at s sits at frame 100 s."""
    ACTIVE = [1., 3., 6.]

    def setUp(self):
        self.ns = parser_namespace()
        self.calls = []

        def interpolate(times, frames, all_frames):
            self.calls.append((list(times), list(frames)))
            return np.interp(all_frames, frames, times)
        self.ns['extrapolate_time_from_clock'] = interpolate

    def align(self, pulses, replay, stopped=None, extra_channels=(), fps=100, active=None, replay_metadata=None):
        n_frames = int(max(pulses) * fps) + 3 * fps
        frames = np.arange(n_frames)

        def trace(starts):
            g = np.zeros(n_frames, dtype=int)
            for start in starts:
                g[int(round(start * fps)):int(round(start * fps)) + max(1, fps // 10)] = 1
            return g

        bits = [trace(pulses)] + [trace(p) for p in extra_channels]
        x = sum(g << (3 + i) for i, g in enumerate(bits))
        log = pd.DataFrame({0: frames, 1: frames / fps, 2: x})
        active = [dict(trial_num=i, t_sync=t) for i, t in enumerate(active or self.ACTIVE)]
        passive = [dict(passive_trial_num=i, t_sync=t) for i, t in enumerate(replay)]
        return self.ns['_handle_chipmunk_camera_sync'](0, log, [], frames, active, passive, stopped, replay_metadata)

    def test_stopped_trial_pulse_between_active_and_replay_is_skipped(self):
        times, _ = self.align([1, 3, 6, 8.5, 11, 13], [11., 13.], stopped=3)
        self.assertEqual(self.calls[0], ([1., 3., 6., 11., 13.], [100, 300, 600, 1100, 1300]))
        self.assertAlmostEqual(times[1100], 11.)

    def test_stopped_pulse_and_one_trailing_aborted_replay_pulse(self):
        self.align([1, 3, 6, 8.5, 11, 13, 16], [11., 13.], stopped=3,
                   replay_metadata=dict(status='aborted', stoppedPulseAfter=2))
        self.assertEqual(self.calls[0][1], [100, 300, 600, 1100, 1300])

    def test_one_trailing_pulse_without_a_stopped_trial(self):
        self.align([1, 3, 6, 11, 13, 16], [11., 13.],
                   replay_metadata=dict(status='aborted', stoppedPulseAfter=2))
        self.assertEqual(self.calls[0][1], [100, 300, 600, 1100, 1300])

    def test_unmarked_extra_pulse_in_the_middle_is_rejected(self):
        with self.assertRaisesRegex(ValueError, r'matching GPIO'):
            self.align([1, 3, 6, 8.5, 11, 13], [11., 13.], stopped=None)
        self.assertEqual(self.calls, [])

    def test_marker_without_a_pulse_is_accepted_when_the_intervals_fit(self):
        # Stop just before a trial starts sets the marker but sends no pulse (README).
        self.align([1, 3, 6, 11, 13], [11., 13.], stopped=3)
        self.assertEqual(self.calls[0][1], [100, 300, 600, 1100, 1300])

    def test_marker_without_a_pulse_and_one_trailing_pulse(self):
        self.align([1, 3, 6, 11, 13, 16], [11., 13.], stopped=3,
                   replay_metadata=dict(status='aborted', stoppedPulseAfter=2))
        self.assertEqual(self.calls[0][1], [100, 300, 600, 1100, 1300])

    def test_marker_with_a_real_pulse_missing_is_rejected(self):
        # The 11 s replay pulse is absent: neither reading of the five pulses fits Bpod.
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 8.5, 13], [11., 13.], stopped=3)
        self.assertEqual(self.calls, [])

    def test_marker_reading_that_cannot_be_decided_is_rejected(self):
        # At 1 frame per second the tolerance is 2 s, so both readings of these six pulses fit Bpod.
        with self.assertRaisesRegex(ValueError, 'too coarse'):
            self.align([2, 4, 6, 8, 10, 12], [10., 12.], stopped=3, fps=1, active=[2., 4., 6.])
        self.assertEqual(self.calls, [])

    def test_marker_that_disagrees_with_the_saved_trials_is_rejected(self):
        for stopped in (0, 2, 4):
            with self.subTest(stopped=stopped):
                with self.assertRaisesRegex(ValueError, 'saved trials'):
                    self.align([1, 3, 6, 8.5, 11, 13], [11., 13.], stopped=stopped)

    def test_two_extra_pulses_without_markers_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 8.5, 11, 13, 16], [11., 13.], stopped=None)

    def test_missing_pulse_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 11], [11., 13.])

    def test_gpio_that_does_not_change_is_rejected(self):
        frames = np.arange(1500)
        log = pd.DataFrame({0: frames, 1: frames / 100, 2: np.zeros(1500, dtype=int)})
        with self.assertRaisesRegex(ValueError, 'no GPIO channel changes'):
            self.ns['_handle_chipmunk_camera_sync'](
                0, log, [], frames, [dict(trial_num=0, t_sync=1.)], [dict(t_sync=3.)])

    def test_a_boundary_blip_on_another_channel_does_not_abort_the_search(self):
        # Real logs flip a bit on the first or last frame; that channel just fails to qualify.
        self.align([1, 3, 6, 8.5, 11, 13], [11., 13.], stopped=3, extra_channels=([14.9],))
        self.assertEqual(self.calls[0][1], [100, 300, 600, 1100, 1300])

    def test_channels_that_qualify_with_different_pulses_are_ambiguous(self):
        # Same number of pulses, offset by three frames: both pass the interval check.
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.align([1, 3, 6, 8.5, 11, 13], [11., 13.], stopped=3,
                       extra_channels=([1.03, 3.03, 6.03, 8.53, 11.03, 13.03],))

    def test_interval_tolerance_is_two_frame_periods(self):
        # Same 0.03 s offset on both replay pulses: 3 frames at 100 Hz fails, 1.5 frames at 50 Hz passes.
        late = [1, 3, 6, 8.5, 11.03, 13.03]
        with self.assertRaisesRegex(ValueError, 'disagree with Bpod'):
            self.align(late, [11., 13.], stopped=3)
        self.align(late, [11., 13.], stopped=3, fps=50)
        self.assertEqual(self.calls[-1][0], [1., 3., 6., 11., 13.])

    def test_periodic_trailing_stop_is_ambiguous_even_with_marker(self):
        for metadata in (None, dict(status='aborted', stoppedPulseAfter=2)):
            with self.subTest(metadata=metadata), self.assertRaises(ValueError):
                self.align([1, 3, 5, 7, 9, 11], [7., 9.], active=[1., 3., 5.], replay_metadata=metadata)

    def test_irregular_trailing_pulse_requires_marker(self):
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 11, 13, 16], [11., 13.])

    def test_ambiguous_channel_cannot_be_hidden_by_another_channel(self):
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.align([2, 4, 6, 8, 10, 12], [10., 12.], stopped=3, fps=1,
                       active=[2., 4., 6.], extra_channels=([2, 4, 6, 10, 12],))

    def test_eventless_replay_does_not_use_legacy_fallback(self):
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 8], [], replay_metadata=dict(status='aborted', stoppedPulseAfter=[]))
        self.align([1, 3, 6, 8], [], replay_metadata=dict(status='aborted', stoppedPulseAfter=0))

    def test_initially_high_gpio_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'initially high'):
            self.align([0, 1, 3, 6, 11, 13], [11., 13.])

    def test_observed_aborted_replay_pulse_does_not_allow_another_trailing_pulse(self):
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 11, 13, 16], [11., 13.],
                       replay_metadata=dict(status='aborted', stoppedPulseAfter=1))


class MarkerPlumbingTest(unittest.TestCase):
    def calls(self, path, name):
        tree = ast.parse((ROOT / path).read_text())
        return [n for n in ast.walk(tree) if isinstance(n, ast.Call)
                and getattr(n.func, 'id', getattr(n.func, 'attr', None)) == name]

    def test_make_passes_the_stopped_trial_marker_to_the_camera_extraction(self):
        calls = self.calls('pluginschema.py', 'extract_chipmunk_camera_data')
        self.assertEqual(len(calls), 1)
        self.assertIn("settingsdict.get('stopped_trial_pulse')", ast.unparse(calls[0]).replace('"', "'"))

    def test_extraction_passes_the_marker_to_the_alignment(self):
        calls = self.calls('utils.py', '_handle_chipmunk_camera_sync')
        self.assertEqual(len(calls), 1)
        self.assertEqual(ast.unparse(calls[0].args[-2]), 'stopped_trial_pulse')
        self.assertEqual(len(calls[0].args), 8)

    def test_parser_returns_the_marker_make_reads(self):
        data = replay_data(['completed', 'completed', 'completed'], 'completed')
        data['StoppedTrialPulse'] = 3
        (_, _, settings), _ = parse(data)
        self.assertEqual(settings['stopped_trial_pulse'], 3)


if __name__ == '__main__':
    unittest.main()


class CameraInputValidationTest(unittest.TestCase):
    def test_invalid_frame_times_do_not_silently_align(self):
        match = parser_namespace()['_replay_gpio_onsets']
        for times in ([0., float('nan'), 2.], [0., 0., 2.], [2., 1., 0.]):
            with self.subTest(times=times), self.assertRaises(ValueError):
                match([(0, [0, 1, 0])], times, [1., 2.], 1)

    def test_invalid_gpio_states_fail_explicitly(self):
        match = parser_namespace()['_replay_gpio_onsets']
        for states in ([0, 2, 0], [0, 1]):
            with self.subTest(states=states), self.assertRaises(ValueError):
                match([(0, states)], [0., 1., 2.], [1., 2.], 1)


class ReviewerBlockersTest(unittest.TestCase):
    def test_zero_observed_rows_keep_replay_status(self):
        (_, _, _), metadata = parse(replay_data(['aborted', 'not_started'], 'aborted', stopped_after=0))
        self.assertEqual(metadata['passive_trials'], [])
        self.assertEqual(metadata['passive_replay']['status'], 'aborted')
        self.assertEqual(metadata['passive_replay']['stoppedPulseAfter'], 0)

    def test_all_verified_nochoice_stopping_producers(self):
        helper = DidNotChooseTest()
        frame = example_session()[0]
        frame['Reward'] = [np.array([np.nan, np.nan])]
        frame['DemonDidNotChoose'] = [np.array([.5, .51])]
        root = ROOT.parent
        paths = list((root / 'Functions/StateMatrices').glob('*.m')) + list((root / 'chipmunk_solo/Functions/StateMatrices').glob('*.m'))
        import re
        stopping = []
        for path in paths:
            block = re.search(r"'Name', 'DemonDidNotChoose'.*?'OutputActions', (.*?);", path.read_text(), re.S)
            if block and re.search(r"'SoftCode',\s*255", block[1]):
                stopping.append(path.stem)
                with self.subTest(producer=path.stem):
                    self.assertAlmostEqual(helper.process(frame, path.stem)['stim_duration'], .3)
        self.assertEqual(len(stopping), 9)
        for producer in ('DemonstratorSelfInitiatedTaskSMA', 'DemonstratorPacedTaskSMA',
                         'DemonstratorPacedFixationTrainingSMA', 'ObserverTaskSMA_outdated', None, 'UnknownLegacy'):
            with self.subTest(producer=producer):
                self.assertAlmostEqual(helper.process(frame, producer)['stim_duration'], 1.5)


class ReviewerValidationTest(unittest.TestCase):
    def test_invalid_bpod_times_and_replay_markers(self):
        match = parser_namespace()['_replay_gpio_onsets']
        for times in ([1, np.nan], [1, 1], [2, 1], [[1, 2]]):
            with self.subTest(times=times), self.assertRaises(ValueError):
                match([(0, [0, 1, 0, 1, 0])], np.arange(5), times, 1)
        for marker in (-1, .5, np.nan, [0, 1], 2):
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                match([(0, [0, 1, 0, 1, 0])], np.arange(5), [1, 3], 1,
                      passive_replay=dict(status='aborted', stoppedPulseAfter=marker))

    def test_invalid_saved_active_stop_markers_fail_before_integer_conversion(self):
        for marker in (-1, 2.5, np.nan, [3, 3]):
            data = replay_data(['completed'], 'completed')
            data['StoppedTrialPulse'] = marker
            with self.subTest(marker=marker), self.assertRaisesRegex(ValueError, 'Invalid StoppedTrialPulse'):
                parse(data)

    def test_ephys_ordinal_guard_runs_before_plugin_inserts(self):
        tree = ast.parse((ROOT / 'pluginschema.py').read_text())
        make = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == 'make')
        guard = next(n for n in ast.walk(make) if isinstance(n, ast.If)
                     and ast.unparse(n.test).startswith('passive_trials and'))
        for rows, marker, fails in [([{}], 3, True), ([{}], None, False), ([], 3, False)]:
            with self.subTest(rows=rows, marker=marker):
                code = compile(ast.Module(body=[guard], type_ignores=[]), 'guard', 'exec')
                env = dict(passive_trials=rows, settingsdict=dict(stopped_trial_pulse=marker))
                if fails:
                    with self.assertRaisesRegex(ValueError, 'physical evidence'):
                        exec(code, env)
                else:
                    exec(code, env)
        inserts = [n.lineno for n in ast.walk(make) if isinstance(n, ast.Call)
                   and getattr(n.func, 'attr', '') in ('insert1', 'insert')]
        self.assertLess(guard.lineno, min(inserts))

    def test_replay_metadata_reaches_extraction_and_matcher(self):
        helper = MarkerPlumbingTest()
        for path, name in [('pluginschema.py', 'extract_chipmunk_camera_data'),
                           ('utils.py', '_handle_chipmunk_camera_sync'),
                           ('utils.py', '_replay_gpio_onsets')]:
            self.assertEqual(ast.unparse(helper.calls(path, name)[0].args[-1]), 'passive_replay')
        tree = ast.parse((ROOT / 'utils.py').read_text())
        extract = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                       and n.name == 'extract_chipmunk_camera_data')
        strict = next(n for n in ast.walk(extract) if isinstance(n, ast.If)
                      and ast.unparse(n.test) == 'passive_trials or passive_replay is not None')
        code = compile(ast.Module(body=[strict], type_ignores=[]), 'strict', 'exec')
        with self.assertRaisesRegex(ValueError, 'Replay camera alignment failed'):
            exec(code, dict(passive_trials=[], passive_replay={'status': 'aborted'},
                            vidfile='fake.avi', err=ValueError('unmatched GPIO')))
