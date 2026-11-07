"""Saved stimulus/replay contracts, without LabData imports or database access."""
from pathlib import Path
import tempfile
import unittest

import numpy as np
from scipy.io import savemat

from test_loader_compatibility import session_data, records
from test_parser_fields import parser_namespace, definition, ROOT
import ast


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

    def test_synchronous_channels_share_one_event_list(self):
        data=session_data()
        data['Modality'][:]=3
        for t in range(3): data['InterStimulusIntervalList'][t,1]=data['InterStimulusIntervalList'][t,0]
        (_,params,_),_=self.parse(data)
        self.assertTrue(all('stim_events_audio' not in p for p in params))
        np.testing.assert_allclose(params[0]['stim_events'],[.2,.415,.63,.845])

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
        from scipy.io import loadmat
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'FakeSubject_contract.mat'
            savemat(path,{'PassiveReplay':data['PassiveReplay']},long_field_names=True)
            replay=loadmat(path,simplify_cells=True)['PassiveReplay']
        self.assertEqual(parser_namespace()['_passive_replay'](replay),expected)
        data['PassiveReplay']['sourceTrialNumbers']=[0,4]
        with self.assertRaisesRegex(ValueError,'source references'):
            self.parse(data)

    def test_single_saved_trial(self):
        (trials,params,_),_=self.parse(session_data(n=1))
        self.assertEqual((len(trials),len(params)),(1,1))

    def test_no_events_do_not_become_a_false_zero_flag(self):
        data=session_data()
        raw=np.empty((1,3),dtype=object)
        for i in range(3): raw[0,i]=np.array([])
        data['PassiveReplay']=dict(sourceTrialNumbers=[1,2,3],nRequested=3,
            nCompleted=0,status='failed',trialStatus=np.array(['failed','not_started','not_started'],dtype=object),
            rawEvents=raw,stateNames=np.array([],dtype=object))
        with self.assertRaisesRegex(ValueError,'no recorded event timestamps'):
            self.parse(data)

    def test_session_without_replay_has_no_passive_rows(self):
        (_,_,settings),metadata=self.parse(session_data())
        self.assertNotIn('passive_replay',settings)
        self.assertEqual(metadata.get('passive_trials',[]),[])

    def test_passive_dataset_links_source_trial(self):
        tree=ast.parse((ROOT/'pluginschema.py').read_text())
        cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='ChipmunkPassive')
        self.assertIn('-> Dataset',cls.body[0].value.value)
        part=next(n for n in cls.body if isinstance(n,ast.ClassDef) and n.name=='Trial')
        ddl=part.body[0].value.value
        self.assertIn("-> Chipmunk.Trial.proj(source_dataset_name='dataset_name', source_trial_num='trial_num')",ddl)
        self.assertIn('passive_trial_num',ddl)
        self.assertNotIn('passive_replay',definition('Chipmunk'))
        self.assertNotIn('Passive',[n.name for n in ast.walk(tree) if isinstance(n,ast.ClassDef)])

    def test_time_columns_preserve_double_precision(self):
        for line in definition('Trial').splitlines():
            if line.strip().startswith('t_') or line.strip().startswith('stim_duration'):
                self.assertEqual(line.split(':')[1].split('#')[0].strip(),'double')


if __name__=='__main__':
    unittest.main()
