# Testing

Run all checks on a rig before deploying (close MATLAB first):

```sh
chipmunk_solo/tests/run_rig_checks.sh           # everything, about an hour
chipmunk_solo/tests/run_rig_checks.sh offline   # or: offline | emulator | real
```

Logs go to `~/chipmunk-rig-checks/<time>/`. Settings for other rigs are at the top of the script.

To run one check by hand, from `chipmunk_solo/` in a fresh MATLAB: `addpath('tests'); check_core_task`.

None of these measure physical LED, sound or TTL timing.

## Offline

| Check | |
|---|---|
| `check_core_task` | Core task logic |
| `check_startup`, `check_prestart_cancel` | Startup, subject names, labcams config, cancel |
| `check_settings_compatibility` | Saved settings load and save |
| `check_stimulus_manipulation` | Manipulation presets and settings notes |
| `check_psychometric_plot`, `check_stimulus_plot_parents` | Plots |
| `check_passive_replay`, `check_stopped_trial_pulse` | Replay and the sync pulse of a stopped trial |
| `check_labcams_udp`, `check_camera_registration` | Camera commands |
| `check_ephys`, `check_ephys_workflow`, `check_ephys_shutdown_order` | Recording workflow and shutdown order |
| `check_spikeglx_devices`, `check_spikeglx_disconnect` | Device selection, connection loss |
| `check_ephys_digital`, `check_ephys_anatomy`, `check_shared_vvasp` | Digital IO, anatomy labels, VVASP records |
| `check_original_isolation` | Original protocol uses its own functions |

## Emulator

Each runs in `Bpod('EMU')`.

| Check | |
|---|---|
| `check_chipmunk_outcomes` | Correct, wrong, early withdrawal, no choice |
| `check_chipmunk_manipulation_session` | All four presets, then replay |
| `check_chipmunk_replay_session` | Full sessions with and without replay |
| `check_passive_replay_emulator` | Replay through the state machine, Stop during replay |
| `check_chipmunk_endurance` | 1,000 trials |

## Real Bpod

`run_rig_checks.sh real` runs `check_chipmunk_replay_session` on the real Bpod with cameras, ending with Stop during a trial and replay.

## By hand

- `check_native_picker`: file picker. Run `python3 tests/native_picker_input.py <folder>` on the rig display alongside it.
- `check_historical_equivalence`: compares the stimulus code to older versions. Needs `python3 tests/prepare_historical_comparison.py <folder>` and the recordings listed there.
- `python3 tests/check_vvasp_anatomy.py`: anatomy coordinate math.

Past validation runs are in [`tests/evidence/`](../tests/evidence).
