"""Replay pulses reach both ephys matching and camera GPIO alignment."""
import unittest
import numpy as np
import pandas as pd
from test_parser_fields import parser_namespace

class ReplaySyncTest(unittest.TestCase):
    def setUp(self):
        self.ns = parser_namespace()
        self.active = [dict(trial_num=i, t_sync=t) for i,t in enumerate([1.,3.,6.])]
        self.passive = [dict(passive_trial_num=i,t_sync=t) for i,t in enumerate([8.,11.])]

    def test_complete_sync_sequence_matches_ephys_edges(self):
        from thesis.ephys.preprocessing.insert_streamsync import _strictly_matched_count
        source = self.ns['_session_sync_times'](self.active,self.passive)
        clock = np.column_stack((source+20,source+20.1)).ravel()
        values = np.tile([1,0],len(source))
        self.assertEqual(_strictly_matched_count(source,np.arange(5),clock,values),5)
        with self.assertRaises(ValueError):
            _strictly_matched_count(source[:3],np.arange(3),clock,values)
        np.testing.assert_equal(self.ns['_session_sync_times'](self.active),[1,3,6])

    def test_stopped_trial_pulse_numbering(self):
        number = self.ns['_bpod_sync_pulse_numbers']
        np.testing.assert_equal(number(3, 2), [0, 1, 2, 3, 4])
        np.testing.assert_equal(number(3, 2, 3), [0, 1, 2, 4, 5])
        np.testing.assert_equal(number(3, 0, 3), [0, 1, 2])  # trailing pulse needs no gap
        with self.assertRaisesRegex(ValueError, 'Stopped-trial pulse after 2'):
            number(3, 2, 2)

    def test_stopped_trial_pulse_pairs_with_ephys_clock(self):
        from thesis.ephys.preprocessing.insert_streamsync import _strictly_matched_count
        source = self.ns['_session_sync_times'](self.active, self.passive)  # 1,3,6 | 8,11
        def clock(onsets):
            onsets = 20 + 1.0001 * np.asarray(onsets)  # offset and drift
            return np.column_stack((onsets, onsets + .1)).ravel(), np.tile([1, 0], len(onsets))
        def match(numbers, onsets):
            return _strictly_matched_count(source, numbers, *clock(onsets),
                                           clock_pulse_numbers=numbers, source_is_bpod=True)
        stopped = self.ns['_bpod_sync_pulse_numbers'](3, 2, 3)
        # Stop cut trial 4 short at 7 s (pulse sent, not saved); replay then ran.
        self.assertEqual(match(stopped, [1, 3, 6, 7, 8, 11]), 5)
        # Plus the trailing pulse of a replay that Stop also cut short.
        self.assertEqual(match(stopped, [1, 3, 6, 7, 8, 11, 13]), 5)
        # Without the gap, replays would pair one pulse early: rejected, not shifted.
        with self.assertRaises(ValueError):
            match(np.arange(5), [1, 3, 6, 7, 8, 11])
        # A marker without its physical pulse is rejected too.
        with self.assertRaises(ValueError):
            match(stopped, [1, 3, 6, 8, 11])

    def test_invalid_sync_cannot_silently_drop_a_pulse(self):
        for stamp in (None,float('nan'),2.):
            with self.assertRaises(ValueError):
                self.ns['_session_sync_times'](self.active,[dict(t_sync=stamp)])

    def test_camera_uses_replay_gpio_markers(self):
        frames=np.arange(1400)
        gpio=np.zeros(len(frames),dtype=int)
        for start in [100,300,600,800,1100]: gpio[start:start+10]=1
        log=pd.DataFrame({0:frames,1:frames/100,2:gpio})
        calls=[]
        def interpolate(times,indices,all_frames):
            calls.append((times,indices))
            return np.interp(all_frames,indices,times)
        self.ns['extrapolate_time_from_clock']=interpolate
        times,events=self.ns['_handle_chipmunk_camera_sync'](0,log,[],frames,self.active,self.passive)
        np.testing.assert_equal(calls[0][0],[1,3,6,8,11])
        np.testing.assert_equal(calls[0][1],[100,300,600,800,1100])
        self.assertEqual(len(events),1)
        self.assertEqual(times[1100],11)
        gpio[800:]=0
        with self.assertRaisesRegex(ValueError,'matching GPIO'):
            self.ns['_handle_chipmunk_camera_sync'](0,pd.DataFrame({0:frames,1:frames/100,2:gpio}),[],frames,self.active,self.passive)

if __name__=='__main__': unittest.main()
