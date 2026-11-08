"""Accounting contract: synthetic MAT files and key-restricted tables; no DB imports."""
import ast
import unittest
import warnings

import numpy as np
import pandas as pd

from test_loader_compatibility import session_data
from test_parser_fields import ROOT, definition, parser_namespace
from test_parser_fixes import parse


class ParserAccountingTest(unittest.TestCase):
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

    def test_P1_P2_passive_identity_and_zero_choice_task(self):
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

    def test_P3_legacy_task_inference(self):
        (_, params, settings), _ = parse(self.data(None))
        self.assertEqual(settings['setting_task_mode'], 'detection')
        self.assertEqual(params[0]['configured_reward_volume'], 3.)

    def test_P4_inconsistent_assembler_rejected(self):
        for index in range(3):
            data = self.data()
            data['TrialSettings']['smaAssembler'][0, index] = 'PassiveVisualStimSMA'
            with self.assertRaisesRegex(ValueError, 'Inconsistent per-trial smaAssembler'):
                parse(data)

    def test_P5_correct_side_snapshot_and_revised_choice(self):
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

    def test_P6_squeezed_single_trial(self):
        (_, params, _), _ = parse(self.data(n=1))
        self.assertEqual(params[0]['configured_reward_volume'], 3.)
        self.assertIsInstance(params[0]['configured_reward_volume'], float)

    def test_P7_empty_and_nan_remain_unknown(self):
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

    def test_scalar_volume_shapes_and_malformed_values(self):
        volume = parser_namespace()['_configured_reward_volume']
        for value in (2., np.array(2.), [2.], np.array([[2.]])):
            self.assertEqual(volume(value), 2.)
        for value in (True, complex(2, 1), None, {'value': 2}):
            with self.assertRaises(ValueError):
                volume(value)

    def test_schema_is_minimal_and_join_attribute_unique(self):
        master, parameters = definition('Chipmunk'), definition('TrialParameters')
        self.assertIn("enum('detection','discrimination','passive')", master)
        self.assertIn('configured_reward_volume = NULL', parameters)
        self.assertNotIn('configured_reward_volume', master)
        self.assertIn("rewarded_position                   : enum('left','right')", parameters)


class KeyRelation:
    """Dictionary restrictions ignore unknown attributes, as DataJoint does."""
    def __init__(self, rows=(), primary_key=()):
        self.rows = list(rows)
        self.primary_key = primary_key

    def __and__(self, key):
        return KeyRelation([row for row in self.rows
                            if all(row[k] == v for k, v in key.items() if k in row)], self.primary_key)

    def __mul__(self, other):
        return KeyRelation([dict(a, **b) for a in self.rows for b in other.rows
                            if all(a[k] == b[k] for k in a.keys() & b.keys())])

    def __bool__(self):
        return bool(self.rows)

    def fetch(self, *args, **kwargs):
        return [r[args[0]] for r in self.rows] if args else self.rows

    def fetch1(self):
        assert len(self.rows) == 1
        return self.rows[0].copy()


class AccountingFixture:
    key = dict(subject_name='DEMO', session_name='one', dataset_name='chipmunk')
    when = '2026-11-08 12:00:00'

    def __init__(self, n=60, **columns):
        frame = pd.DataFrame(dict(trial_num=np.arange(n), setting_task_mode='detection',
            configured_reward_volume=2., rewarded_position='left', response=1, rewarded=1,
            setting_left_reward_volume=2., setting_right_reward_volume=6.,
            initiated=1, early_withdrawal=0, punished=0, with_choice=1,
            rewarded_modality='visual', stim_rate_vision=6., stim_rate_audio=np.nan,
            category_boundary=12., t_response=1., t_gocue=.5, t_initiate=.2, t_start=0.))
        for name, value in dict(self.key, **columns).items():
            frame[name] = value
        chip = KeyRelation([self.key])
        chip.Trial = KeyRelation(frame.to_dict('records'))
        chip.TrialParameters = KeyRelation([self.key])
        dataset = KeyRelation([self.key])
        session = KeyRelation([dict(subject_name='DEMO', session_name='one', session_datetime=self.when)])
        self.water = KeyRelation(primary_key=('subject_name', 'watering_datetime'))
        self.decision = KeyRelation(primary_key=tuple(self.key))
        self.decision.TrialSet = KeyRelation(primary_key=(*self.key, 'trialset_description'))
        self.writes = []
        ns = parser_namespace()
        fn = next(n for n in ast.parse((ROOT / 'utils.py').read_text()).body
                  if isinstance(n, ast.FunctionDef) and n.name == 'chipmunk_insert_decision_task')
        fn.body = [n for n in fn.body if not isinstance(n, (ast.Import, ast.ImportFrom))]
        ns.update(Chipmunk=chip, Dataset=dataset, Session=session, Watering=self.water,
                  DecisionTask=self.decision, _upsert_generated_row=self.upsert)
        exec(compile(ast.Module(body=[fn], type_ignores=[]), 'accounting', 'exec'), ns)
        self.insert = ns['chipmunk_insert_decision_task']

    def upsert(self, table, row):
        self.writes.append((table, row.copy()))
        table.rows[:] = [old for old in table.rows
                         if any(old[k] != row[k] for k in table.primary_key)]
        table.rows.append(row.copy())

    def run(self, mintrials=50):
        with warnings.catch_warnings(record=True) as messages:
            warnings.simplefilter('always')
            self.insert(self.key, mintrials=mintrials)
        return messages


class DecisionAccountingTest(unittest.TestCase):
    def test_D1_passive_writes_nothing(self):
        f = AccountingFixture(setting_task_mode='passive')
        f.run()
        self.assertEqual(f.writes, [])

    def test_D2_zero_choice_task_records_zero_water(self):
        f = AccountingFixture(response=0, rewarded=0, with_choice=0)
        f.run()
        self.assertEqual(f.water.rows[0]['water_volume'], 0.)
        self.assertEqual(f.decision.rows[0]['n_total_trials'], 60)

    def test_D3_changed_volume(self):
        f = AccountingFixture(configured_reward_volume=[2.] * 30 + [4.] * 30)
        f.run()
        self.assertAlmostEqual(f.water.rows[0]['water_volume'], .180)

    def test_D4_revised_choice_uses_correct_side(self):
        f = AccountingFixture(response=1, rewarded_position='left')
        f.run()
        self.assertAlmostEqual(f.water.rows[0]['water_volume'], .120)

    def test_D5_D6_unknown_fallback_by_correct_side_warns_once(self):
        for values, expected in [([None] * 60, .120), ([None] * 30 + [4.] * 30, .180)]:
            f = AccountingFixture(configured_reward_volume=values)
            messages = f.run()
            self.assertAlmostEqual(f.water.rows[0]['water_volume'], expected)
            self.assertEqual(sum('trial-zero correct-side' in str(m.message) for m in messages), 1)

    def test_D7_short_task_and_empty(self):
        for n in (0, 1, 20, 49, 50):
            f = AccountingFixture(n=n)
            f.run()
            self.assertEqual(len(f.decision.rows), int(n > 0))
            self.assertEqual(len(f.water.rows), int(n > 0))
            self.assertEqual(len(f.decision.TrialSet.rows), int(n >= 50))
            if n:
                self.assertEqual(f.decision.rows[0]['n_total_trials'], n)
                self.assertAlmostEqual(f.water.rows[0]['water_volume'], n * .002)

    def test_thresholds_and_modality_more_than_ten(self):
        for n, minimum, expected in [(10, 1, 0), (11, 1, 1), (60, 61, 0)]:
            f = AccountingFixture(n=n)
            f.run(minimum)
            self.assertEqual(len(f.decision.TrialSet.rows), expected)
        f = AccountingFixture(rewarded_modality=['visual'] * 10 + ['audio'] * 50,
                              stim_rate_audio=6.)
        f.run()
        self.assertEqual([r['trialset_description'] for r in f.decision.TrialSet.rows], ['audio'])

    def test_D8_D10_manual_row_kept_and_retry_stays_unlinked(self):
        f = AccountingFixture(n=20)
        manual = dict(subject_name='DEMO', watering_datetime=f.when, water_volume=.8)
        f.water.rows.append(manual.copy())
        for _ in range(2):
            f.run()
            self.assertEqual(f.water.rows, [manual])
            self.assertIsNone(f.decision.rows[0]['watering_datetime'])
            self.assertFalse(any(table is f.water for table, _ in f.writes))

    def test_historically_linked_manual_water_is_not_overwritten(self):
        f = AccountingFixture()
        manual = dict(subject_name='DEMO', watering_datetime=f.when, water_volume=.8)
        f.water.rows.append(manual.copy())
        f.decision.rows.append(dict(f.key, watering_datetime=f.when))
        messages = f.run()
        self.assertEqual(f.water.rows, [manual])
        self.assertFalse(any(table is f.water for table, _ in f.writes))
        self.assertTrue(any('estimate differs' in str(m.message) for m in messages))

    def test_D9_generated_retry_is_idempotent(self):
        f = AccountingFixture(n=20)
        f.run()
        first = [(table, row.copy()) for table, row in f.writes]
        f.writes.clear()
        f.run()
        self.assertEqual(f.writes, first)
        self.assertEqual(len(f.water.rows), 1)
        self.assertEqual(len(f.decision.rows), 1)

    def test_other_keys_do_not_prove_ownership_or_block_insert(self):
        f = AccountingFixture(n=20)
        manual = dict(subject_name='DEMO', watering_datetime=f.when, water_volume=.8)
        f.water.rows.append(manual.copy())
        f.decision.rows.append(dict(f.key, session_name='other', watering_datetime=f.when))
        f.run()
        self.assertEqual(f.water.rows, [manual])
        own = (f.decision & f.key).fetch1()
        self.assertIsNone(own['watering_datetime'])
        f = AccountingFixture(n=20)
        f.water.rows.append(dict(manual, subject_name='OTHER'))
        f.run()
        self.assertEqual(len(f.water.rows), 2)
        self.assertEqual((f.decision & f.key).fetch1()['watering_datetime'], f.when)

    def test_invalid_stored_or_fallback_volume_fails_before_writes(self):
        for volume in (-1., np.inf, 'bad', [1., 2.]):
            f = AccountingFixture(configured_reward_volume=[volume] * 60)
            with self.subTest(volume=volume), self.assertRaises(ValueError):
                f.run()
            self.assertEqual(f.writes, [])
        f = AccountingFixture(configured_reward_volume=None, setting_left_reward_volume=np.nan)
        with self.assertRaisesRegex(ValueError, 'unknown trial-zero'):
            f.run()
        self.assertEqual(f.writes, [])
