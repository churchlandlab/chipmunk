# Chipmunk accounting contract and deployment

Implementation baseline: isolated candidate `t3-9b527036`, commit
`4bafcb1be75c3c1780782999134e12e3150354a2`, reviewed 2026-11-08.
This preserves the relevant Opus accounting trace supplied by the parent and
records the parent's accepted choices. No live database evidence was collected.

## Saved data and estimates

`Chipmunk.TrialParameters.configured_reward_volume = NULL : float` is the
correct-side `TrialSettings` calibration target in **uL**, on every task trial,
whether rewarded or not. It is never a measurement of delivered water.
The name is unique to the part: sharing a master attribute name would silently
add a natural-join condition in `Chipmunk.trial_query`. No other schema columns
or nullability changes are part of this change.

Verified in this candidate:

- `chipmunk_solo/chipmunk_solo.m` applies GUI updates before constructing the
  state matrix, then calls `retrieveTrialData` in the same loop pass.
- `chipmunk_solo/Functions/retrieveTrialData.m` snapshots ProtocolSettings and
  saves `CorrectSide` from TrialSidesList.
- `MultipleModalitiesTaskSMA.m` uses `correctSideOnCurrent == 0` for the left
  valve and leftRewardVolume, otherwise right valve and rightRewardVolume.
  The parser maps saved 0 to `left` and 1 to `right`; other codes fail.
- `PassiveVisualStimSMA.m` has no choice or valve states. Only exact saved
  `SettingsFile.smaAssembler == 'PassiveVisualStimSMA'` means passive. TaskPhase
  is not assembler identity. Any per-trial assembler, when present, must match
  the session identity, including rejecting per-trial identities without a
  matching session identity.

The supplied cross-producer trace reports original revise-choice sessions can
save the first poke as ResponseSide even when a different correct-side valve
is rewarded. Thus a rewarded left trial with first poke right, left target 2
and right target 6, contributes **2 uL**, not 6. The trace reports GUI/snapshot
ordering also holds in the original and forks; those producers were not run
here. Legacy files without assembler identity retain rate-based task inference.
Their task identity is an inference from producer history, not proof from the
file; no new passive detection heuristic is introduced.

Per-trial scalar or singleton-array volumes normalize to floats; empty and NaN
become NULL, with no trial-zero substitution during parsing. Negative, infinite,
non-numeric and multi-valued volumes fail. Both saved side settings are validated.
Single-trial squeezed MAT files are supported. Initial session volume columns
remain trial-zero settings with their existing non-null schema; a missing initial
value does not gain new master-column nullability in this migration.
Passive trials always have NULL configured volume, even if their settings carry
an unused reward target.

## Session summaries and ownership

`chipmunk_insert_decision_task` returns without writes for empty joins or passive
sessions. Every nonempty task session, including fewer than 50 trials and tasks
with zero choices, gets DecisionTask and an estimated Watering entry, subject to
the existing manual-water collision rule. `mintrials` (default 50) gates only
TrialSet creation; each modality must still have more than 10 trials.

Estimated water in mL is `sum(rewarded * configured_reward_volume) / 1000`.
Only NULL values fall back to the trial-zero **correct-side** setting, with one
fallback warning per invocation. Known trial values are preserved. Unknown or
invalid fallback values fail before any writes rather than silently undercount.
A 60-trial rewarded session with thirty 2 uL and thirty 4 uL targets estimates
0.180 mL. Sixty revised left rewards at 2 uL estimate 0.120 mL, regardless of
first poke. Zero rewarded trials estimate zero water.

The existing ownership rule is unchanged: an unlinked Watering row at that
subject/time is preserved and DecisionTask's watering link stays NULL, including
on retries. A currently linked row is upserted on retry. **Historic links do not
prove generated ownership**: old code linked existing manual rows too. This is
not a safe historic repopulation tool. A preserved manual collision means the
earned estimate is not stored separately under the existing schema.

Tests use synthetic MAT files and key-restricted table doubles. P1-P7 and
D1-D10 cover identity, legacy inference, snapshots, singleton files, unknown
values, changing targets, revised choices, short/empty sessions, manual
collisions, and retry idempotence. Additional checks cover invalid values,
unrelated subject/session keys, default/custom thresholds and modality sizes.
Existing parser, camera/replay and cross-repository thesis sync tests also run.
No physical water-delivery or live database validation is implied.

## Required live work (not performed)

1. Review the schema diff for every configured user/Chipmunk schema. Before
   deploying new code, **ADD nullable configured_reward_volume** to
   Chipmunk.TrialParameters and **append 'passive'** to setting_task_mode's enum.
   Old code is compatible with the extended schema; new code fails against the
   old schema. Do not run an alter from `make()` or inside its transaction.
2. Before any backfill, produce a read-only impact report from saved MAT files
   and current rows. List per-trial targets, compare rewarded target sums with
   saved LeftSideRewardAmount + RightSideRewardAmount, and retain mismatches.
   Separate changing-target effects from revise-choice side effects. Include
   short sessions gaining summaries and their manual-water collisions.
3. Review historical ownership individually. Recompute the old formula using
   response side, trial-zero values and float32 arithmetic; agreement within a
   documented small tolerance is a screening check, not ownership proof.
   Historic/manual collisions need human review before overwrites. Any approved
   backfill must update rows in place. **Never delete/repopulate Chipmunk**:
   its trials are referenced by passive replay and DecisionTask can remain stale.
4. Passive cleanup requires a concrete reviewed dataset/row list and separate
   authorization. A link and zero water alone do not prove ownership. No passive
   deletion, repopulation, migration, backfill or cleanup is authorized here.

## Downstream impact and remaining limits

The supplied downstream source trace says chipmunk-dashboard lists sessions from
DecisionTask.TrialSet, so its session list remains threshold-gated. Its settings
panel can expose the added field; its uniform-step water curve may need a future
update to represent variable targets. Built-in LabData activity based on
DecisionTask includes short tasks, and watering plots/totals include their earned
estimates. Counts of DecisionTask sessions increase; `n_total_trials >= 50`
retains the prior length criterion, with passive excluded on new ingestion.
Historical dashboards/counts do not change until separately approved live work;
no live affected-session counts were measured. The contract's thesis trace uses
explicit trial projections rather than these summaries; local cross-repository
sync tests guard compatibility, with no thesis edits.

Observer-subject watering remains unchanged and is not newly accounted here.
Reward and response detection now use exact task state names. Unrecognized
reward-like states and an unknown assembler without defined task outcome states
raise before ingestion, rather than being interpreted as zero earned water.
Missing trial-zero volumes also raise explicitly because the existing master
volume columns are NOT NULL; no zero or first-known substitute is invented.
An existing linked Watering row whose amount differs from the new estimate is
preserved with a warning. This protects historical links that do not prove
ownership; changing those amounts requires the separately reviewed backfill.
Saved reward totals are an internal consistency check, never proof of actual
water. Camera/replay guards remain unchanged; physical sync ordinal ambiguity
remains pending hardware evidence.
