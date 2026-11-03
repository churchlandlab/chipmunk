# Chipmunk behavioral import

The plugin reads Chipmunk and Chipmunk Solo MAT files. Active trials remain in
`Chipmunk.Trial` and `TrialParameters`. Stand-alone passive sessions use
`setting_task_mode='passive'`; they have no choice, reward or rewarded position.

## Stimulus timing

`stim_events` contains intended pulse onsets relative to each trial start,
including repeats in `ExtraStimulusDuration`. It represents the visual channel
for multisensory trials, or the active channel for unisensory trials.
`stim_events_audio` contains multisensory audio onsets only when they differ;
NULL means shared timing for multisensory trials. No synchrony flag is needed.

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

`Chipmunk.passive_replay` stores the saved `SessionData.PassiveReplay` record,
separately from active trial rows. It retains selection/order, statuses,
durations, raw events, state-name mapping and error information. MATLAB's
`sourceTrialNumbers` remain **one-based**; subtract one to join to `trial_num`.
Invalid source references or completion counts raise a parsing error.

Raw event cells are stored as Python lists for DataJoint 0.14 serialization.
Empty failed/aborted records remain empty. Older aborted files with no timestamps
cannot supply a replay onset, duration or partial exposure; do not infer one
from the intended duration or session completion status.

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
Changing these definitions does not migrate existing SQL tables. Back up current
rows and affected metadata before a separate, explicitly scoped live rebuild.
