# Chipmunk behavioral import

The plugin reads Chipmunk and Chipmunk Solo MAT files. Active trials remain in
`Chipmunk.Trial` and `TrialParameters`. Stand-alone passive sessions use
`setting_task_mode='passive'`; they have no choice, reward or rewarded position.

## Stimulus timing

`stim_events` contains intended pulse onsets relative to each trial start,
including repeats in `ExtraStimulusDuration`. It represents the visual channel
for multisensory trials, or the active channel for unisensory trials.
Multisensory trials use one shared event list: the supported workflow is
synchronous visual/audio stimulation. There is no supplemental audio column.

Both MATLAB protocols generate at 192 kHz. Reconstruction rounds gaps to samples,
pads channels to their shared length, and repeats the resulting waveform.
`stim_duration` is limited by recorded withdrawal/response when available.
Intended pulse lists do not establish actual exposure on an interrupted trial;
use recorded states and hardware events for that question. Audio noise samples
cannot be recovered from interval lists.

Trial state timestamps include `TrialStartTimestamp`; preserve this existing
clock origin when joining to other streams. Time columns use SQL DOUBLE.
FLOAT setting columns retain their existing precision.

## Passive replay

`Chipmunk.passive_replay` is 0 or 1, based on the presence of recorded replay
observations. `Chipmunk.Passive` stores one row per replayed trial:

- The inherited Chipmunk key plus zero-based `passive_trial_num` identifies order.
- `source_trial_num` is a foreign key to the original `Chipmunk.Trial`. MATLAB's
  one-based source references are converted to zero-based trial numbers.
- Nullable DOUBLE `t_sync`, `t_stim` and `t_stim_end` are recorded Sync,
  PlayStimulus and StopStimulus onsets. They share the active session's Bpod
  clock: raw TrialStartTimestamp plus the relative state time. No clock reset
  or stitching by intended duration occurs.

Source-trial settings are referenced rather than copied. No replay status or
summary columns are stored. Missing event records fail import instead of
fabricating timestamps or a false zero flag; unstarted selections produce no
observation rows. Raw MAT files retain the original status/error information.
The Solo protocol's one-second first-onset target affects future recordings;
historical replay timestamps retain their actual measured gaps.

## Repopulation

Repopulating after a Chipmunk-only rebuild reuses existing weighings. A conflicting
weight is preserved with a warning. Existing note attachments are preserved;
Session experimenter and Dataset setup still come from saved metadata.

Plugin-generated sync, video and decision summaries are updated without SQL
REPLACE or deletion of referenced rows. A watering record already linked to the
session's DecisionTask is refreshed; an unlinked existing watering is preserved
with a warning and is not claimed by the plugin. Summaries use rewarded choices
for `n_correct`; passive sessions do not create decision-task summaries.

Input files are retained regardless of `LABDATA_DELETE_FILES_AFTER_POPULATE`.
File cleanup belongs outside `make()`, after a successful population commit.
Changing these definitions does not migrate existing SQL tables. Full backups
must include all four Chipmunk tables, including Passive. Back up current rows
and affected metadata before a separate, explicitly scoped live rebuild.
