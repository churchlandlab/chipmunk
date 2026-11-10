"""Replay pulses reach both ephys matching and camera GPIO alignment."""
import re
import unittest
import numpy as np
import pandas as pd
from test_parser_fields import parser_namespace

class ReplaySyncTest(unittest.TestCase):
    def setUp(self):
        self.ns = parser_namespace()
        self.active = [dict(trial_num=i, t_sync=t) for i,t in enumerate([1.,3.,6.])]
        self.passive = [dict(passive_trial_num=i,t_sync=t) for i,t in enumerate([8.,11.])]


    def test_stopped_trial_pulse_numbering(self):
        number = self.ns['_bpod_sync_pulse_numbers']
        np.testing.assert_equal(number(3, 2), [0, 1, 2, 3, 4])
        np.testing.assert_equal(number(3, 2, 3), [0, 1, 2, 4, 5])
        np.testing.assert_equal(number(3, 0, 3), [0, 1, 2])  # trailing pulse needs no gap
        with self.assertRaisesRegex(ValueError, 'Stopped-trial pulse after 2'):
            number(3, 2, 2)


    def test_idle_high_non_sync_line_does_not_block_replay_alignment(self):
        # Venus RightView 20261106_234931: gpio1 idles high; gpio2 has 3 active,
        # the unsaved Stop pulse, then 3 replay pulses.
        t = np.arange(600) * .0125
        onsets = np.array([131, 194, 253, 316, 368, 475, 506])
        sync = np.zeros(600, dtype=int)
        for o in onsets: sync[o:o + 8] = 1
        idle = np.ones(600, dtype=int); idle[-1] = 0
        got = self.ns['_replay_gpio_onsets']([(1, idle), (2, sync)], t, np.delete(t[onsets], 3) + 50,
                                             n_active=3, stopped_trial_pulse=3)
        np.testing.assert_equal(got, np.delete(onsets, 3))
        with self.assertRaisesRegex(ValueError, 'initially high'):  # a high sync line still fails
            self.ns['_replay_gpio_onsets']([(1, idle)], t, np.delete(t[onsets], 3) + 50, n_active=3)

    def test_network_log_fallback_pairs_labcams_trial_numbers(self):
        # No GPIO: labcams logs trials from 1 (4 = stopped, unsaved); trial_num starts at 0.
        frames = [147, 227, 296, 353]
        comm = [f'# {f},{f * .0125:.6f} - trial_start[   0]: {k + 1}' for k, f in enumerate(frames)]
        log = pd.DataFrame({0: np.arange(400), 1: np.arange(400) * .0125, 2: np.zeros(400, dtype=int)})
        trials = [dict(trial_num=k, t_sync=56 + frames[k] * .0125) for k in range(3)]
        self.ns['re'] = re
        times, _ = self.ns['_handle_chipmunk_camera_sync'](0, log, comm, range(400), trials)
        np.testing.assert_allclose(times, 56 + np.arange(400) * .0125, atol=1e-9)
        with self.assertRaisesRegex(ValueError, 'two matched sync anchors'):  # never stores NaN
            self.ns['_handle_chipmunk_camera_sync'](0, log, comm[:1], range(400), trials)

    def test_frame_times_fit_one_line_through_quantized_anchors(self):
        fit = self.ns['_frames_to_bpod_time']
        period, n = .0125, 3000
        true = 10 + np.arange(n) * period * (1 + 20e-6)  # 20 ppm clock difference
        sync = 10 + np.array([.7, 3.1, 4.4, 7.9, 9.2, 12.6])  # Bpod sync times inside the video
        first_seen = np.searchsorted(true, sync)  # anchors are late by up to one frame
        err = np.abs(fit(sync, first_seen, n) - true)
        self.assertLess(err.max(), period)  # within a frame, including far extrapolation
        piecewise = np.interp(np.arange(n), first_seen, sync)
        piecewise[first_seen[-1]:] = sync[-1] + (np.arange(first_seen[-1], n) - first_seen[-1]) * (
            (sync[-1] - sync[-2]) / (first_seen[-1] - first_seen[-2]))
        self.assertLess(err.max(), np.abs(piecewise - true).max())
        # A camera whose rate changes keeps piecewise interpolation, with a warning.
        self.ns['extrapolate_time_from_clock'] = lambda t, f, x: np.interp(x, f, t)
        with self.assertWarnsRegex(UserWarning, 'constant frame rate'):
            fit([0., 1., 2., 4.], [0, 100, 200, 250], 300)

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
        fit=self.ns['_frames_to_bpod_time']
        def anchors(times,indices,n_frames,**kwargs):
            calls.append((times,indices))
            return fit(times,indices,n_frames,**kwargs)
        self.ns['_frames_to_bpod_time']=anchors
        times,events=self.ns['_handle_chipmunk_camera_sync'](0,log,[],frames,self.active,self.passive)
        np.testing.assert_equal(calls[0][0],[1,3,6,8,11])
        np.testing.assert_equal(calls[0][1],[100,300,600,800,1100])
        self.assertEqual(len(events),1)
        self.assertAlmostEqual(times[1100],11)
        gpio[800:]=0
        with self.assertRaisesRegex(ValueError,'matching GPIO'):
            self.ns['_handle_chipmunk_camera_sync'](0,pd.DataFrame({0:frames,1:frames/100,2:gpio}),[],frames,self.active,self.passive)

if __name__=='__main__': unittest.main()
