# Unified solo task audit — 2026-11-01

What this repo does: Runs one mouse's visual/auditory discrimination or passive stimulus session through Bpod, with optional cameras, optional SpikeGLX recording and post-session replay. Expected load is one session per rig, up to 5,000 trials; deterministic saved trial parameters and reliable shutdown matter more than throughput.

This audit covers the main protocol, initialization and GUI callbacks, all shipped state assemblers, trial processing, stimulus builders, anti-bias updates, plotting and replay. The bundled sound server was read but retained, including its device/calibration behavior. Hardware design assets and external repositories are outside this audit.

## Findings addressed

1. **Passive trials failed or ended before the waveform.** The passive matrix immediately exited PlayStimulus, while trial processing unconditionally accessed missing choice states. It now waits for the actual loaded waveform duration, honors its configured ITI, sends stop at completion, and records no choice or reward when choice states are absent. Legacy delay and outcome field names remain. Tests cover both synthetic passive records and real Bpod emulation.

2. **The trial limit bypassed saving.** Exhausting the main loop previously returned without normal teardown. Natural completion now calls the same finish function as Stop, including replay and saving. The unchanged 5,000-trial default uses the same termination path exercised by the bounded completion test and endurance fixture. Stop during preparation is also checked before sending another state matrix.

3. **Notebook text was used as a format string.** A note containing `%` or a backslash could be changed by fprintf. The writer now uses a fixed format with the note as an argument. MAT saving still precedes text-note writing.

4. **Zero-rate stimulus generation indexed an empty event list.** It now returns one silent train interval. Invalid pulse/gap combinations fail with a specific error instead of falling through with an undefined bin array. Tests check zero, normal event count/duration and invalid bin sizes.

5. **Wait-time residuals double-counted the exponential extra wait.** SetWaitTime already includes PostStimDelay. The plot now subtracts SetWaitTime and PreStimDelay once. Scatter colors use one value per point in a column, matching MATLAB's graphics contract. The regression checks a known 0.7 s hold against a 0.1 s pre-delay and 0.6 s required wait.

6. **Miniscope tools were removed.** The unused Python/Teensy sync path, startup fields, cleanup tests and dummy STL are gone. Leave `miniscopeID` in old settings files; the task no longer reads them.

7. **Obsolete code hid the supported task flow.** Removed unreachable observer-paced LED toggles and the unused LEDswitch helper, and removed the unsupported choice-revision processing branch. Assembler outputs and saved ReviseChoiceFlag, PacedFlag, DidNotInitiate and virtualObsInitDelay fields remain for compatibility. Shortened obsolete two-animal headers, revision narratives, separator banners and commented-out plotting code. Kept timing/calibration explanations and anti-bias mathematics. Replaced string-built assembler and initialization eval calls with direct function calls and dynamic field access.

8. **GUI config selection could overwrite its path on Cancel.** Cancel now leaves the current selection unchanged. GUI tests exercise actual preset callbacks, Update behavior, enabled fields and Save settings round trips. Screenshot capture is part of the full manipulation emulator test.

## Follow-up fixes

9. **The selected camera config now applies on cold and warm startup.** The installed labcams version accepts a JSON path as a positional argument. The task validates that file and passes a shell-quoted path. An explicit config restarts an already-open app before recording; a blank config retains the current app. The GUI retains saved selections. Real-camera tests used a temporary config with distinct camera names and 72 fps, including starting with a different 80 fps config already open. Both cameras recorded the selected names at 72 fps, with continuous frame IDs matching video frame counts: cold 198/197 frames, warm 196/196 frames.

10. **Reserved subjects fail clearly before device startup.** Virtual/Dummy no longer skip the save-path creation and then crash later. Validation rejects those names and directs the operator to FakeSubject plus Bpod emulator mode. Initialization publishes the full metadata struct once, rather than changing UserData field by field. Closing initialization resets Bpod to idle. GUI/validation/cancellation regression checks pass.

11. **Repeated-session automation no longer uses stale driver callbacks.** Test timers are explicitly deleted between sessions; callbacks from invalid or replaced drivers return immediately. The driver test deliberately invokes a deleted timer's callback and checks that no timer remains. GUI error cleanup checks handle validity, preserving the original error report. Six consecutive active/passive sessions and a subsequent manipulation session passed in one interpreter, including the formerly troublesome fourth/fifth starts. No fixed four-session condition is present in the task. A later expanded outcome batch exposed a separate missed-ready-state startup race, now fixed and retested as described below.

12. **Natural completion now also resets the Bpod console.** A short optional trial-count argument exercises the same loop termination used by the unchanged 5,000-trial default. This exposed an additional outcome-plot bug: initial/future points indexed beyond the side list, including near the last trial. Plot bounds now respect available trials and clear the current marker once complete. Focused plot tests cover the end boundary; the bounded full-session test covers save and idle teardown.

## Remaining validation boundaries

- Follow-up isolated the startup race: Initialize could complete before waitfor began waiting for a new UserData change. Startup now waits for a target ready value and retrieves complete metadata from appdata. The combined six-session outcome sequence passes after this fix; other unenumerated manual sequences are not claimed exhaustive.

- Physical LED/audio/TTL timing, calibrated luminance and live SpikeGLX acquisition require hardware measurements. Camera selection and video continuity were tested with real cameras; that does not establish precise stimulus synchronization. ALSA device warnings persist in emulation.
- Numeric GUI expressions retain MATLAB's existing evaluator for the trusted local operator interface.

## Reproducing the checks

In a fresh MATLAB session:

```matlab
addpath('tests');
check_startup;
check_core_task;
check_stimulus_manipulation;
check_passive_replay;
check_psychometric_plot;
check_ephys;
```

Start fresh idle Bpod with `Bpod('EMU')` (Mercury also requires its emulator Start button). Consecutive-session validation deliberately stays in that interpreter:

```matlab
addpath('tests');
check_chipmunk_replay_session(fullfile(tempdir,'solo-limit'), {'VisualTask'}, '', 3);
check_chipmunk_replay_session(fullfile(tempdir,'solo-repeat'), ...
    {'VisualTask','MultipleModalitiesTask','VisualTask','PassiveVisualStim','VisualTask','PassiveVisualStim'});
check_chipmunk_manipulation_session(fullfile(tempdir,'solo-manipulation'));
```

For a camera test, pass the selected JSON as the third argument to `check_chipmunk_replay_session`; this intentionally starts real camera recording. Keep output/configs isolated from animal data.

The manipulation test captures the real Task control window for each added preset under its output `gui/` directory. Earlier combined runs intermittently stalled with invalid timer/GUI handles. The callback guards, explicit ownership/deletion checks and six-session regression supersede the fresh-interpreter workaround. Logs remain in the local work directory. Verified Mercury results (MATLAB R2022b Update 1, Bpod Console 1.71):

- Three full active sessions passed: nine active trials and six replays, including replay off/on and another session.
- A separate passive session passed: three complete stimulus trains, no valid choices or reward, correct saved events and shutdown.
- Real replay checks passed: selection, restart, Stop during ITI/playback, intentional errors, saved statuses and state-name mapping.
- Eight manipulation trials and eight replays passed: saved effective parameters and notes at trials 3/5/7 remained correct and active data were unchanged. Preset selection callbacks are invoked before Update, matching mouse selection behavior.
- Four new-panel screenshots were captured from the full manipulation session. Labels on the new replay/manipulation panels were shortened to avoid clipping; parameter names and saved values are unchanged.

Evidence: `/tmp/chipmunk-notes-20261101-152744` (all isolated suites) and `/tmp/chipmunk-notes-20261101-153213` (final GUI captures). Downloaded logs and MAT files remain in the local work directory. Local MATLAB core, GUI/save, replay and psychometric checks passed; Python cleanup checks passed. The state-machine checks used emulation; the config-selection tests used real cameras.

Verdict: The startup missed-ready-state race is fixed and the combined outcome sequence passes. Physical output measurements remain separate and need a recording return path.


Final follow-up evidence: `/tmp/chipmunk-notes-20261101-155712` contains a bounded natural-completion session, six consecutive active/passive sessions and the manipulation session in one interpreter: eight sessions, 29 trials and 23 replays. Timer deletion and intentionally late-callback checks passed. `/tmp/chipmunk-cameras-20261101-155153` contains cold/warm real-camera tests, each with three saved trials. Independent MAT readback confirmed session/trial/replay counts; ffprobe and frame logs confirmed all four videos' frame counts and 72 fps metadata. Local startup, core, GUI/save, replay and psychometric checks passed. At that checkpoint, the default 5,000-trial session length had not been exercised; the later workload check is recorded below.


## Expanded outcome and modality matrix

The new `check_chipmunk_outcomes` fixture checks five full-session outcomes for both correct sides in each of three modalities. Expected saved outcomes are `[1, 0, -1, -1, 2]`; only the first two are valid choices, only the first receives reward, and early pre-stimulus withdrawal must never reach PlayStimulus. The check also compares the saved MAT fields against the pre-stop snapshot.

The manipulation fixture now accepts modality and multisensory timing mode. It checks each preset's effective brightness/pulse/minimum interval, notes at the correct trial boundaries, all replay source mappings/durations, unchanged active arrays and both reconstructed channels. For auditory comparisons, the test controls random state on both reconstructions; it does not claim original noise samples were recovered.

The cases run in fresh, bounded emulator processes after an initial combined batch stalled at later-session startup. That failure was subsequently isolated to the startup ready-state race and fixed; the combined sequence and native picker now pass, as described below. The outcome matrix alone does not test 5,000-trial endurance or physical output timing/fidelity.


Expanded matrix results: all 11 isolated cases passed on Mercury under `/tmp/chipmunk-notes-20261101-161606`: six outcome sessions (30 trials) and five preset/modality/timing sessions (40 trials, 40 replays). Independent SciPy readback confirmed the 70 saved trial records, expected outcome vectors, no-choice timeout duration, manipulation parameters, three notes per manipulation session and replay source mappings. Local regressions also passed. The initial combined run under `/tmp/chipmunk-notes-20261101-161315` stalled at a later startup. The follow-up below supersedes that open issue with the diagnosed race, fix and passing combined run. No task implementation changes were needed for the passing isolated outcome/modality cases themselves.


## Startup-ready race and native picker follow-up

The source of the intermittent startup hang was an event-order race: Initialize could publish its data before the main function reached `waitfor(fig,'UserData')`. That form waits for a later change, and repeated identical submissions need not generate one. Startup now publishes complete input data in appdata and sets a boolean ready flag; `waitfor(fig,'UserData',true)` also returns when completion already occurred. Controls remain hidden until fully built, and cancellation normalizes deleted-window errors and resets idle. Local startup/core/GUI/replay/psychometric regressions pass, including an already-ready wait and cancellation.

Native file-picker Open and Cancel were tested through actual X11 mouse/keyboard input from a separate process, not by invoking a modal chooser inside a timer callback. The final selected path survived Open, reopening, Cancel and Initialize. The screenshot in the README comes from that test. Early automation attempts are retained as diagnostics; opening the chooser from the timer test harness was not treated as a production UI failure.

The previously troublesome combined sequence was rerun after the fix in one interpreter: both response sides across visual, auditory and multisensory outcomes all passed. The shared endurance fixture also passed a 100-trial natural-completion cross-check. Evidence is under Mercury `/tmp/chipmunk-gaps-20261101-163106` and the matching local work directory.

Gabriel confirmed that TTL/soundcard/speaker/PWM/LED outputs are not connected to any recording input. Consequently there is no available remote measurement of physical TTL, acoustic or optical timing. Output commands/waveforms and recorded camera continuity do not establish those physical measurements.


## Workload check and final saved-data verification

Gabriel clarified that mice do not reach 1,000 trials and requested ending the longer run. The emulator was stopped with the real Bpod Stop button after **3,870 completed trials**. The task saved, closed its sound server and exited; Bpod emulation closed as well. The original fixture then failed its `numel(data.Modality) == 5000` assertion because of the requested early stop. This is evidence of a completed 3,870-trial stress workload and Stop/save behavior, not a passing 5,000-trial natural-completion test.

Independent SciPy readback verified nTrials=3,870, matching lengths for 28 trial fields and all raw trial events, expected correct/left/valid outcomes, no replay, and 30,960 µL of simulated left reward (3,870 × 8 µL), zero right reward. Every raw trial reached PlayStimulus, DemonReward and FinishTrial. The downloaded MAT SHA-256 matches Mercury: `77561d5db1ee9bea19d49331202614b5660953d1b80270038665f6496cf1eebf`. The separate 100-trial shared-fixture run passed natural completion, saved-data, idle-state and sound-server teardown assertions; independent readback confirmed it too. The fixed combined outcome batch's six MAT files independently match the expected five outcomes each.

The committed routine endurance wrapper now requests 1,000 trials; it reuses the shared full-session fixture. The production limit remains 5,000. Both workload runs use short holds/delays and real Bpod emulation, waveform generation, GUI plotting and saving. The long run was briefly paused while the native picker had keyboard focus. These are software workload checks rather than normal-duration animal sessions or physical output measurements. Memory at late checkpoints remained around 1.9 GB. Evidence: `/tmp/chipmunk-gaps-20261101-163106` and local `work/gaps-validation-20261101-163106/independent-final-verification.json`.


## Final review, saved settings and rollout preparation

What this change does: The shared runner supports per-trial manipulation, replay and saved compatibility fields. This final review traced startup, GUI updates, trial generation, event processing, replay, saving and teardown at one session per rig and fewer than 1,000 expected animal trials.

Two further defects were confirmed and fixed:

1. **Invalid replay Enable could prevent the natural-completion save** (`Functions/Utilities/runPassiveReplaySession.m`). GUI synchronization and Enable validation ran before the replay error handler. A blank, NaN or nonbinary edit could throw from the final completion path before shutdown saved active data. They now run inside the existing handler and cleanup guard, producing failed replay metadata while preserving active records. The new regression failed before the fix and passes afterward; the real emulator checks saved natural completion with an invalid edit.
2. **Delayed two-interval multisensory trains had unequal channel lengths** (`chipmunk_solo.m`, `Functions/StimulusPlotDemonstrator.m`). Shuffled or independently generated visual timing adds 20 ms, yielding a 1.02 s visual channel alongside 1 s audio. Concatenating those rows crashed. The shorter channel now receives trailing silence, preserving stimulus onsets. The plot now uses the actual sample count and expands or contracts its axis accordingly. Tests check waveform plotting at 1.02 s and back at 1 s, plus visual, auditory and all three multisensory timing modes through real emulation.

An obsolete replay assembler comment claiming the passive assembler still had zero-duration playback was removed. No other confirmed source-level finding remains open from this review.

The settings check reads files, exercises the real GUI/Update/Save callbacks and writes only temporary copies. It preserves existing values while adding missing defaults. All three shipped experiment settings and all **13 configured Mercury settings files** passed; the other **12 files** are empty Bpod-created DefaultSettings placeholders and are explicitly skipped. These include settings copied from the solo and older half-second/ephys folders; this does not validate an ephys runtime integration. All 25 live settings files still match the pre-test copy byte for byte. Production remains clean at `bc8095c02ccd38b875ad493289d414d452b514fe`.

The [Mercury rollout and rollback guide](../mercury-rollout.md) records exact paths, backup commands, candidate verification, short emulator checks and recovery steps. Deployment has not been executed. Use a configured task settings file rather than an empty DefaultSettings placeholder. The original 0.5 s base-wait default is supplied only when missing; calibration and existing settings are retained.

Final Mercury verification passed in one interpreter under `/tmp/chipmunk-final-review-20261101-171752`: 10 sessions, 40 saved active trials and 6 completed replays. The batch covers normal and invalid-replay natural completion, three consecutive replay sessions and five two-interval modality/timing cases. Independent SciPy readback verified all 10 MAT files, expected outcome vectors and failed/completed replay statuses. No graphics shape warnings remain. Local startup, core/plot, GUI/manipulation, replay, psychometric and shipped-settings checks passed. Detailed evidence is retained under local `work/final-review-*`.

Verdict: Ship. This source-review verdict does not establish physical output timing or authorize deploying a running rig; use the rollout guide for a controlled checkout. Physical LED/audio/TTL timing and calibrated levels, live SpikeGLX behavior and hardware-mode acquisition were not checked in this final review.


## Historical task equivalence

Compared the new runtime at c0158b3 against five pinned source references. The standard active Poisson path preserves the tested recent half-second task behavior under the same settings and calibration. It is not universally identical to every historical Chipmunk variant.

| Reference | Standard stimulus samples | State-command comparison against the half-second default |
| --- | --- | --- |
| Solo PR base bc8095c | 135/135 identical | 18/18 identical, including LEDs |
| Archived half-second 0577522 | 135/135 identical | 18/18 identical, including LEDs |
| May 2024 half-second d14d96a | 135/135 identical | 18/18 core timer/choice/output cases match after separating port LEDs; 6/18 full cases match because its visual task used LEDs |
| Original chipmunk a112fde | 135/135 identical | 6/18 match under the new half-second default; exponential cases require the original one-second baseline |
| Ephys a451cf9 with its half-second import at 0577522 | 135/135 identical | Imported behavior assemblers match 18/18; recording integration was not tested |

The 135 stimulus cases combine three random seeds, rates 4/12/20 Hz, visual/auditory and three multisensory timing modes, and extra durations 0/0.25/1.25 s. Each version executes its own main-loop stimulus code extracted verbatim between fixed source boundaries, with the display and device-upload calls omitted. External helper functions come from the corresponding source tree. Comparisons use exact software sample hashes, including regenerated auditory noise under identical seeds. All 18 cue-sound sets and all 12 tested bias-update input combinations also match each reference.

State comparison captures all timers, transitions, BNC, SoftCode and valve commands. A shared deterministic valve-calibration substitute prevents differences in calibration files from obscuring the code comparison. Core comparisons separate PWM port-LED actions; the full comparison retains them. Empty output lists and command-pair ordering are normalized. These tests do not upload a matrix or measure real valve/TTL timing.

### Confirmed historical differences

- **Port LEDs:** the earlier visual task switched port LEDs during trials. Commit [119a9d6, July 25, 2025](https://github.com/churchlandlab/half_second_chipmunk_solo/commit/119a9d6) removed them. The new VisualTask preserves that later lights-off behavior. The new MultipleModalitiesTask assembler retains its existing LED behavior; choose the matching assembler when comparing an older task.
- **One-second versus half-second exponential hold:** the original task uses 1 s plus a random extra hold. The recent half-second task and the missing-baseWait fallback use 0.5 s plus that task's extra hold. Setting baseWait=1 and using the LED-preserving MultipleModalitiesTask assembler gives 6/6 full state-machine matches to the original one-second reference. This is a settings selection, not a new code change.
- **Training progression:** the May 2024 half-second source capped its increasing numeric hold at 0.5 s. Commit [f0b5963, October 21, 2024](https://github.com/churchlandlab/half_second_chipmunk_solo/commit/f0b5963) changed that cap to 0.6 s. The new code matches the later cap and the solo PR base; it does not reproduce the early staircase automatically. Fixed-hold mature trials with a zero increment retain their configured hold.
- **Legacy settings names:** the July 2024 recording names DemonstratorTaskSMA, which is absent from the new solo runner. The comparison explicitly maps it to MultipleModalitiesTaskSMA. A historical settings file is not thereby proven launchable unchanged; preserve values while mapping its phase/assembler deliberately.
- **Other paths:** the PR intentionally fixes passive playback, zero-rate failure, alternate-generator channel alignment and several save/error paths. Optional manipulation and replay modes deliberately change behavior when enabled. Those are outside this standard positive-rate active-task equivalence claim.

### Recorded-session checks

| Recorded session | Trials | Saved task conditions | Recomputed classification |
| --- | ---: | --- | --- |
| GRB006 20240723_142451 | 831 | Multisensory, despite the DemonstratorAudiTask filename; fixed 0.5 s hold, zero hold increment | Exact match |
| GRB063 20261030_134253 | 268 | Visual, 0.5 s baseline plus random extra hold | Exact match |
| GRB064 20261030_151009 | 244 | Visual; exponential half-second settings, then zero hold on the final 13 trials | Exact match |

All 1,343 saved trials were reprocessed through the new, base-solo, archived-half and original processing functions using the actual saved events, settings and delays. Eleven compared fields match exactly: outcomes, reward flags, early withdrawals, no-choice/no-initiation flags, response side, correctness, validity, actual hold time and left/right reward totals. Every saved intended train in these sessions is 1 s with 15 ms pulses and at least 25 ms between pulses. Early withdrawal or choice can shorten actual exposure; the intended train is not a measurement of delivered light/sound.

The recorded completed-hold intervals agree with their saved timer values within 0.1 ms. None of these MAT files records a Git source commit. They validate saved parameters/events, while the explicitly pinned snapshots establish source-level comparisons; they do not prove which unrecorded checkout produced every old session. Hardware calibration changes and exact original noise samples cannot be recovered from these tests.

The complete comparison passed on local MATLAB R2024b and Mercury R2022b Update 1 with identical result reports. Mercury evidence: `/tmp/chipmunk-historical-equivalence-20261101-175808`; local inputs/logs: `work/history-equivalence`. [Public evidence and source hashes](../../tests/evidence/historical-equivalence-2026-11-01.json) omit the animal MAT files. Reproduce with prepare_historical_comparison.py and check_historical_equivalence as documented in the README. No production task code or rig deployment was changed by this comparison.
