# Testing

Run each check in a fresh MATLAB, from `chipmunk_solo/tests`:

```sh
matlab -batch "check_core_task"
matlab -batch "addpath('~/Bpod_Gen2'); startBpodEmulator; check_chipmunk_outcomes(tempname,1,1)"
```

None of these measure physical LED, sound or TTL timing.

## Offline

| Check | |
|---|---|
| `check_core_task` | Core task logic |
| `check_startup` | Startup, subject names, labcams config, cancel |
| `check_settings_compatibility` | Saved settings load and save |
| `check_stimulus_manipulation` | Manipulation presets and settings notes |
| `check_psychometric_plot`, `check_stimulus_plot_parents` | Plots |
| `check_passive_replay` | Replay |
| `check_labcams_udp` | Camera commands |
| `check_ephys`, `check_ephys_workflow`, `check_ephys_shutdown_order` | Recording workflow and shutdown order |
| `check_spikeglx_devices`, `check_spikeglx_disconnect` | Device selection, connection loss |
| `check_ephys_digital`, `check_ephys_anatomy`, `check_shared_vvasp` | Digital IO, anatomy labels, VVASP records |

## Emulator

Each runs after `startBpodEmulator` and takes an output folder.

| Check | |
|---|---|
| `check_chipmunk_outcomes` | Correct, wrong, early withdrawal, no choice |
| `check_chipmunk_manipulation_session` | All four presets, then replay |
| `check_chipmunk_replay_session` | Full sessions with and without replay, Stop during a trial |
| `check_passive_replay_emulator` | Replay through the state machine, Stop during replay |
| `check_chipmunk_endurance` | 1,000 trials |

## Real Bpod

With `CHIPMUNK_REAL_BPOD_CHECK=1` set, `check_chipmunk_replay_session(folder,{'VisualTask','MultipleModalitiesTask'},cameraConfig)` runs on the real Bpod with cameras, ending with Stop during a trial and replay.

## By hand

`python3 tests/check_vvasp_anatomy.py`: anatomy coordinate math. Needs the VVASP environment.
