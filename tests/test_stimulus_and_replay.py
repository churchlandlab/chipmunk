"""Saved stimulus/replay contracts, without LabData imports or database access."""
from pathlib import Path
import tempfile
import unittest

import numpy as np
from scipy.io import savemat

from test_loader_compatibility import session_data, records
from test_parser_fields import parser_namespace, definition


class StimulusReplayTest(unittest.TestCase):
    def parse(self, data):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'FakeSubject_contract.mat'
            savemat(path, {'SessionData':data}, long_field_names=True)
            return parser_namespace()['process_chipmunk_file'](str(path))

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

    def test_distinct_audio_is_stored_without_a_synchrony_flag(self):
        data=session_data()
        data['Modality'][:]=3
        for t in range(3): data['InterStimulusIntervalList'][t,1]=[.01,.1,.2]
        (_,params,_),_=self.parse(data)
        self.assertIsNotNone(params[0]['stim_events_audio'])
        self.assertNotIn('synchrony',params[0])
        np.testing.assert_allclose(params[0]['stim_events_audio'],[.21,.325])
        for t in range(3): data['InterStimulusIntervalList'][t,1]=data['InterStimulusIntervalList'][t,0]
        (_,params,_),_=self.parse(data)
        self.assertTrue(all(p['stim_events_audio'] is None for p in params))

    def test_passive_trials_have_no_choice_or_reward_and_keep_duration(self):
        data=session_data()
        values={name:data['TrialSettings'][name][0,0] for name in data['TrialSettings'].dtype.names}
        data['TrialSettings']=records(dict(values,smaAssembler='PassiveVisualStimSMA'),3)
        data['ResponseSide']=np.full(3,np.nan)
        data['CorrectSide']=np.full(3,np.nan)
        for trial in data['RawEvents']['Trial'][0]:
            trial['States']={name:np.array(times) for name,times in [
                ('Sync',[0,.1]),('TrialStart',[.1,.2]),
                ('PlayStimulus',[.2,1.2]),('FinishTrial',[1.2,1.2])]}
            trial['Events']={'Tup':np.array([.1,.2,1.2])}
        (trials,params,settings),_=self.parse(data)
        self.assertEqual(settings['setting_task_mode'],'passive')
        for t,p in zip(trials,params):
            self.assertEqual((t['rewarded'],t['punished'],t['with_choice'],t['initiated']),(0,0,0,0))
            self.assertIsNone(t['t_response'])
            self.assertGreater(t['stim_duration'],0)
            self.assertIsNone(p['rewarded_position'])

    def test_replay_is_separate_and_preserves_unknown_aborted_timing(self):
        data=session_data()
        data['PassiveReplay']=dict(sourceTrialNumbers=[1,3],nRequested=2,
            nCompleted=0,status='aborted',trialStatus=np.array(['aborted','not_started'],dtype=object),
            rawEvents=np.array([{},np.array([])],dtype=object),stateNames=np.array([],dtype=object))
        (trials,_,settings),_=self.parse(data)
        self.assertEqual(len(trials),3)
        replay=settings['passive_replay']
        np.testing.assert_array_equal(replay['sourceTrialNumbers'],[1,3])
        self.assertEqual(replay['rawEvents'][0],{})
        self.assertEqual(replay['nCompleted'],0)
        data['PassiveReplay']['sourceTrialNumbers']=[0,4]
        with self.assertRaisesRegex(ValueError,'source references'):
            self.parse(data)

    def test_single_saved_trial(self):
        (trials,params,_),_=self.parse(session_data(n=1))
        self.assertEqual((len(trials),len(params)),(1,1))

    def test_failed_replay_empty_cells_use_portable_lists(self):
        data=session_data()
        raw=np.empty((1,3),dtype=object)
        for i in range(3): raw[0,i]=np.array([])
        data['PassiveReplay']=dict(sourceTrialNumbers=[1,2,3],nRequested=3,
            nCompleted=0,status='failed',trialStatus=np.array(['failed','not_started','not_started'],dtype=object),
            rawEvents=raw,stateNames=np.array([],dtype=object))
        (_,_,settings),_=self.parse(data)
        self.assertIsInstance(settings['passive_replay']['rawEvents'],list)
        self.assertEqual(len(settings['passive_replay']['rawEvents']),3)
        self.assertTrue(all(np.size(x)==0 for x in settings['passive_replay']['rawEvents']))

    def test_time_columns_preserve_double_precision(self):
        for line in definition('Trial').splitlines():
            if line.strip().startswith('t_') or line.strip().startswith('stim_duration'):
                self.assertEqual(line.split(':')[1].split('#')[0].strip(),'double')


if __name__=='__main__':
    unittest.main()
