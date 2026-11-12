"""Pairing camera GPIO pulses with Bpod sync pulses, including replay and Stop pulses.

GPIO traces are synthetic unless a test names the recording it copies.
"""
import re
import unittest

import numpy as np
import pandas as pd

from helpers import parser_namespace


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
        fit=self.ns['extrapolate_time_from_clock']
        def anchors(times,indices,frames):
            calls.append((times,indices))
            return fit(times,indices,frames)
        self.ns['extrapolate_time_from_clock']=anchors
        times,events=self.ns['_handle_chipmunk_camera_sync'](0,log,[],frames,self.active,self.passive)
        np.testing.assert_equal(calls[0][0],[1,3,6,8,11])
        np.testing.assert_equal(calls[0][1],[100,300,600,800,1100])
        self.assertEqual(len(events),1)
        self.assertAlmostEqual(times[1100],11)
        gpio[800:]=0
        with self.assertRaisesRegex(ValueError,'matching GPIO'):
            self.ns['_handle_chipmunk_camera_sync'](0,pd.DataFrame({0:frames,1:frames/100,2:gpio}),[],frames,self.active,self.passive)


class CameraPulseTest(unittest.TestCase):
    """Default 100 Hz frames, camera and Bpod clocks identical, so a pulse at s sits at frame 100 s."""
    ACTIVE = [1., 3., 6.]

    def setUp(self):
        self.ns = parser_namespace()
        self.calls = []

        fit = self.ns['extrapolate_time_from_clock']

        def anchors(times, frames, x):
            self.calls.append((list(times), list(frames)))
            return fit(times, frames, x)
        self.ns['extrapolate_time_from_clock'] = anchors

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

    def test_marker_with_a_real_pulse_missing_is_rejected(self):
        # The 11 s replay pulse is absent: neither reading of the five pulses fits Bpod.
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 8.5, 13], [11., 13.], stopped=3)
        self.assertEqual(self.calls, [])

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

    def test_interval_tolerance_is_two_frame_periods(self):
        # Same 0.03 s offset on both replay pulses: 3 frames at 100 Hz fails, 1.5 frames at 50 Hz passes.
        late = [1, 3, 6, 8.5, 11.03, 13.03]
        with self.assertRaisesRegex(ValueError, 'disagree with Bpod'):
            self.align(late, [11., 13.], stopped=3)
        self.align(late, [11., 13.], stopped=3, fps=50)
        self.assertEqual(self.calls[-1][0], [1., 3., 6., 11., 13.])

    def test_irregular_trailing_pulse_requires_marker(self):
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 11, 13, 16], [11., 13.])

    def test_eventless_replay_does_not_use_legacy_fallback(self):
        with self.assertRaisesRegex(ValueError, 'matching GPIO'):
            self.align([1, 3, 6, 8], [], replay_metadata=dict(status='aborted', stoppedPulseAfter=[]))
        self.align([1, 3, 6, 8], [], replay_metadata=dict(status='aborted', stoppedPulseAfter=0))

    def test_initially_high_gpio_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'initially high'):
            self.align([0, 1, 3, 6, 11, 13], [11., 13.])


if __name__ == '__main__':
    unittest.main()
