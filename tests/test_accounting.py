"""Water and performance rows written by chipmunk_insert_decision_task, on in-memory tables."""
import ast
import unittest
import warnings

import numpy as np
import pandas as pd

from helpers import ROOT, parser_namespace


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
    def test_passive_writes_nothing(self):
        f = AccountingFixture(setting_task_mode='passive')
        f.run()
        self.assertEqual(f.writes, [])

    def test_zero_choice_task_records_zero_water(self):
        f = AccountingFixture(response=0, rewarded=0, with_choice=0)
        f.run()
        self.assertEqual(f.water.rows[0]['water_volume'], 0.)
        self.assertEqual(f.decision.rows[0]['n_total_trials'], 60)

    def test_changed_volume(self):
        f = AccountingFixture(configured_reward_volume=[2.] * 30 + [4.] * 30)
        f.run()
        self.assertAlmostEqual(f.water.rows[0]['water_volume'], .180)

    def test_revised_choice_uses_correct_side(self):
        f = AccountingFixture(response=1, rewarded_position='left')
        f.run()
        self.assertAlmostEqual(f.water.rows[0]['water_volume'], .120)

    def test_unknown_fallback_by_correct_side_warns_once(self):
        for values, expected in [([None] * 60, .120), ([None] * 30 + [4.] * 30, .180)]:
            f = AccountingFixture(configured_reward_volume=values)
            messages = f.run()
            self.assertAlmostEqual(f.water.rows[0]['water_volume'], expected)
            self.assertEqual(sum('trial-zero correct-side' in str(m.message) for m in messages), 1)

    def test_short_task_and_empty(self):
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

    def test_manual_row_kept_and_retry_stays_unlinked(self):
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

    def test_generated_retry_is_idempotent(self):
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


class EasyPerformanceTest(unittest.TestCase):
    """Easy trials are those at the largest |stim_rate - boundary|, whichever side it is on."""

    def easy(self, stim_rates, rewarded):
        stim_rates, rewarded = list(stim_rates) * 3, list(rewarded) * 3  # TrialSet rows need more than 10 trials
        f = AccountingFixture(n=len(stim_rates), stim_rate_vision=np.asarray(stim_rates, float),
                              rewarded=rewarded, punished=[1 - r for r in rewarded])
        f.run(mintrials=1)
        return float(f.decision.TrialSet.rows[0]['performance_easy'])

    def test_symmetric_design(self):
        # stim_int is +/-6 at the extremes: 3 of 4 rewarded.
        self.assertEqual(self.easy([6, 18, 6, 18, 9, 15], [1, 1, 1, 0, 0, 1]), .75)

    def test_larger_negative_extreme_defines_easy(self):
        # stim_int -10 (3 of 4 rewarded) and +4 (0 of 2). The signed maximum selected the +4 trials.
        self.assertEqual(self.easy([2, 2, 2, 2, 16, 16], [1, 1, 0, 1, 0, 0]), .75)

    def test_all_negative_design_is_scored(self):
        # stim_int -10, -6, -2: the signed maximum (-2) matched no |stim_int|, which scored 0.
        self.assertEqual(self.easy([2, 2, 6, 6, 10, 10], [1, 0, 1, 1, 1, 1]), .5)


if __name__ == '__main__':
    unittest.main()
