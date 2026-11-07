# Chipmunk behavioral import

The plugin reads Chipmunk and Chipmunk Solo MAT files. Active trials remain in
`Chipmunk.Trial` and `TrialParameters`.

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

Passive replay is a separate labdata dataset. Chipmunk Solo saves the replay in
`<subject>/<session>/chipmunk_passive/` and uploads that folder after
`chipmunk/`. `ChipmunkPassive` reads it:

- One master row per passive dataset, with `replay_order` and `replay_status`.
- `ChipmunkPassive.Trial` has one row per replayed trial. Zero-based
  `passive_trial_num` is the replay order.
- `source_dataset_name` and `source_trial_num` are a foreign key to the original
  `Chipmunk.Trial` in the same session. MATLAB's one-based source references
  are converted to zero-based trial numbers. Stimulus settings and events come
  from that source trial. The replay plays what the mouse saw in that trial: the
  train stops where the task stopped it (reward, wrong choice or no choice), so
  use `t_stim_end` rather than the source trial's intended `stim_events` end.
- Nullable DOUBLE `t_sync`, `t_stim` and `t_stim_end` are recorded Sync,
  PlayStimulus and StopStimulus onsets on the task dataset's Bpod clock (raw
  TrialStartTimestamp plus the relative state time). Convert them with the
  `chipmunk` dataset's StreamSync; the passive dataset has no sync stream.

Populate `Chipmunk` before `ChipmunkPassive`; its key source waits for the task
dataset of the same session. Missing event records fail import instead of
fabricating timestamps; unstarted selections produce no rows. Raw MAT files keep
the full status and error information. The Solo protocol's one-second first-onset
target affects future recordings.

Both tables set an empty `Dataset.dataset_type`: `task-behavior` for `chipmunk`
and `passive-stimulation` for `chipmunk_passive`. The populating account needs
UPDATE on `Dataset`.

## Repopulation

Repopulating after a Chipmunk-only rebuild reuses existing weighings. A conflicting
weight is preserved with a warning. Existing note attachments are preserved;
Session experimenter and Dataset setup still come from saved metadata.

Plugin-generated sync, video and decision summaries are updated without SQL
REPLACE or deletion of referenced rows. A watering record already linked to the
session's DecisionTask is refreshed; an unlinked existing watering is preserved
with a warning and is not claimed by the plugin. Summaries use rewarded choices
for `n_correct`.

A bulk rebuild can skip the camera-video download (about 4 TB for all
sessions): `Chipmunk.populate(..., make_kwargs=dict(download_videos=False))`
downloads the other files, uses the videos only when all of them are already
local, and otherwise leaves the existing camera rows unchanged.

Input files are retained regardless of `LABDATA_DELETE_FILES_AFTER_POPULATE`.
File cleanup belongs outside `make()`, after a successful population commit.
Changing these definitions does not migrate existing SQL tables. Full backups
must include the Chipmunk tables and ChipmunkPassive. Back up current rows
and affected metadata before a separate, explicitly scoped live rebuild.

## Replay synchronization

The Bpod sync event includes active and replay Sync timestamps in acquisition
order. Its event values are pulse ordinals, not source-trial foreign keys;
source trial identity is in ChipmunkPassive.Trial. The sync stream needs every
pulse, so the task file keeps the replay record and `Chipmunk` reads it only for
sync. `ChipmunkPassive` reads the copy in `chipmunk_passive/`. Camera GPIO
alignment uses the same complete pulse list. Replay sessions with unmatched camera GPIO
pulses fail population rather than silently omitting camera alignment or using
active-only network comments. Active-only camera fallback remains unchanged.
