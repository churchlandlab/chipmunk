# labdata plugin

Imports sessions from both protocols.

- `Chipmunk`: one row per session, with `Trial` and `TrialParameters`
- `ChipmunkPassive`: passive replay, with one `Trial` row per replayed trial

Populate `Chipmunk` before `ChipmunkPassive`.

## Trials

- `rewarded` and `t_response` come from the `Reward`/`DemonReward` and `WrongChoice`/`DemonWrongChoice` states, matched by exact name. Any other state with "Reward" in its name fails the import.
- `stim_events` are the intended pulse onsets from trial start, including repeats. For multisensory trials they're the visual channel.
- `stim_duration` is cut at withdrawal, response or no choice. The no-choice cut only applies to state matrices that stop the stimulus on no choice.
- `configured_reward_volume` is the target volume for the correct side (µL), not the water delivered.
- Times are on the Bpod clock from `TrialStartTimestamp`.

## Passive replay

Solo saves replay to `<subject>/<session>/chipmunk_passive/`. Each `ChipmunkPassive.Trial` row links to its source trial in `Chipmunk.Trial` (`source_trial_num`) and has `t_sync`, `t_stim` and `t_stim_end` on the task's Bpod clock. Use `t_stim_end` for when the stimulus stopped; replay stops where the original trial did.

## Sync

Every trial and replay sends a sync pulse. If Stop cuts a trial short, its pulse is sent but the trial isn't saved; Solo marks this with `StoppedTrialPulse`, and the replay pulses are numbered past it.

Camera frame times are interpolated between the frames where sync pulses arrive. If no camera input carries the sync, the labcams log is used instead.

## Repopulating

`Chipmunk.populate(..., make_kwargs=dict(download_videos=False))` skips downloading the videos and keeps the existing camera rows. Existing weighings, notes and watering records are kept. Input files are not deleted.

## Schema changes

This version adds two columns. Apply them to a schema before importing with it:

```sql
ALTER TABLE `<schema>`.`_chipmunk__trial_parameters` ADD COLUMN `configured_reward_volume` float DEFAULT NULL COMMENT 'correct-side TrialSettings calibration target [uL], not measured water', ALGORITHM=INSTANT;
ALTER TABLE `<schema>`.`_chipmunk` MODIFY COLUMN `setting_task_mode` enum('detection','discrimination','passive') NOT NULL, ALGORITHM=INSTANT;
```
