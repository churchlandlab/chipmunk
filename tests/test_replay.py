"""Passive replay rows and the Stop markers."""
from pathlib import Path
import tempfile
import unittest

import numpy as np
from scipy.io import loadmat, savemat

from helpers import parse, parser_namespace, replay_data, session_data


class ReplayTest(unittest.TestCase):
    parse = staticmethod(parse)


    def test_replay_rows_use_session_clock_and_zero_based_source_keys(self):
        data=session_data()
        raw=np.empty((1,2),dtype=object)
        for i in range(2):
            raw[0,i]=dict(TrialStartTimestamp=100.+i*2,
                States=np.arange(1,6),StateTimestamps=[0.,.1,.2,1.2,1.25,1.26])
        data['PassiveReplay']=dict(sourceTrialNumbers=[1,3],nRequested=2,
            nCompleted=2,status='completed',trialStatus=np.array(['completed','completed'],dtype=object),
            rawEvents=raw,stateNames=np.array(['Sync','InterTrialInterval','PlayStimulus','StopStimulus','FinishTrial'],dtype=object))
        (trials,_,settings),metadata=self.parse(data)
        self.assertEqual(len(trials),3)
        self.assertNotIn('passive_replay',settings)
        expected=[
            dict(passive_trial_num=0,source_trial_num=0,t_sync=100.,t_stim=100.2,t_stim_end=101.2),
            dict(passive_trial_num=1,source_trial_num=2,t_sync=102.,t_stim=102.2,t_stim_end=103.2)]
        self.assertEqual(metadata['passive_trials'],expected)
        # The chipmunk_passive copy gives the same rows without the task trials.
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'FakeSubject_contract.mat'
            savemat(path,{'PassiveReplay':data['PassiveReplay']},long_field_names=True)
            replay=loadmat(path,simplify_cells=True)['PassiveReplay']
        self.assertEqual(parser_namespace()['_passive_replay'](replay),expected)
        data['PassiveReplay']['sourceTrialNumbers']=[0,4]
        with self.assertRaisesRegex(ValueError,'source references'):
            self.parse(data)

    def test_stopped_trial_pulse_marker(self):
        (_,_,settings),_=self.parse(session_data())
        self.assertIsNone(settings['stopped_trial_pulse'])
        data=session_data(); data['StoppedTrialPulse']=3
        (_,_,settings),_=self.parse(data)
        self.assertEqual(settings['stopped_trial_pulse'],3)

    def test_session_without_replay_has_no_passive_rows(self):
        (_,_,settings),metadata=self.parse(session_data())
        self.assertNotIn('passive_replay',settings)
        self.assertEqual(metadata.get('passive_trials',[]),[])


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

    def test_zero_observed_rows_keep_replay_status(self):
        (_, _, _), metadata = parse(replay_data(['aborted', 'not_started'], 'aborted', stopped_after=0))
        self.assertEqual(metadata['passive_trials'], [])
        self.assertEqual(metadata['passive_replay']['status'], 'aborted')
        self.assertEqual(metadata['passive_replay']['stoppedPulseAfter'], 0)


if __name__ == '__main__':
    unittest.main()
