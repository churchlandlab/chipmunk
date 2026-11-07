# Mercury rollout and rollback

Current Mercury runtime: `db1fee9` (November 4, 2026), with all three protocol selections linked to the tested ephys/anatomy candidate. The latest checkpoint and rollback are at the end of this document.

Prepared November 1, 2026 for [PR #6](https://github.com/churchlandlab/chipmunk_solo/pull/6). The migration checkpoint below records the executed Mercury deployment; the original preparation steps remain for reference.

## Verified starting point

- SSH route: `ssh -J hodgkin anne@mercury.local`, with Mercury password authentication.
- Production checkout: `/home/anne/Bpod Local/Protocols/chipmunk_solo`, clean at `bc8095c02ccd38b875ad493289d414d452b514fe`.
- Bpod data/settings root: `/home/anne/data`. Bpod configuration is `/home/anne/Bpod Local/Settings/BpodSettings.mat`; sound/water calibration lives under `/home/anne/Bpod Local/Calibration Files`.
- MATLAB R2022b Update 1; Bpod Console 1.71. Existing configured settings lack `baseWait`; the runner supplies the historical 0.5 s default. New manipulation/replay fields are added only when missing.
- Thirteen configured settings files passed real GUI/Update/Save round trips on temporary copies. Twelve empty Bpod-generated DefaultSettings files are placeholders, not task configurations. Select VisualTask or PassiveVisualStim as appropriate; do not launch an empty DefaultSettings file.

Use an idle rig with no animal and close MATLAB/Bpod before changing the checkout. Stop if the checkout has new local work. Do not overwrite settings or calibration with files from the test checkout.

## Back up before switching

Run on Mercury after checking `git status --short` is empty:

```sh
cd '/home/anne/Bpod Local/Protocols/chipmunk_solo'
git status --short
backup="/home/anne/chipmunk-rollbacks/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
git rev-parse HEAD > "$backup/head.txt"
git symbolic-ref --short -q HEAD > "$backup/branch.txt" || true
tar -czf "$backup/protocol.tgz" -C '/home/anne/Bpod Local/Protocols' chipmunk_solo
find /home/anne/data -path '*/Session Settings/*.mat' -type f -print0 |
    tar --null -T - -czf "$backup/session-settings.tgz"
tar -czf "$backup/bpod-config-calibration.tgz" -C '/home/anne/Bpod Local' Settings 'Calibration Files'
find /home/anne/data -path '*/Session Settings/*.mat' -type f -print0 |
    sort -z | xargs -0 sha256sum > "$backup/settings-sha256.txt"
tar -tzf "$backup/protocol.tgz" > "$backup/protocol-files.txt"
tar -tzf "$backup/session-settings.tgz" > "$backup/settings-files.txt"
```

Keep the backup path. The protocol archive includes its Git metadata and any untracked files. The settings archive contains settings only, not animal sessions.

## Switch to the reviewed candidate

```sh
git fetch origin fix/passive-replay
candidate=$(git rev-parse FETCH_HEAD)
printf '%s\n' "$candidate"
```

Compare that SHA with the approved PR head before proceeding. Then:

```sh
git switch --detach "$candidate"
git status --short
testroot="/tmp/chipmunk-rollout-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$testroot/settings"
tar -xzf "$backup/session-settings.tgz" -C "$testroot/settings"
printf '%s\n' "$testroot"
```

If the switch refuses because files would be overwritten, stop and preserve those files. Do not force it.

## Short software checkout

Start fresh MATLAB on Mercury. Substitute the printed testroot below. Before starting Bpod:

```matlab
addpath('/home/anne/Bpod Local/Protocols/chipmunk_solo/tests');
check_settings_compatibility('/tmp/chipmunk-rollout-TIMESTAMP/settings');
Bpod('EMU');
```

Click **Start in emulation mode** if Console 1.71 presents that button. Then:

```matlab
global BpodSystem
assert(BpodSystem.EmulatorMode == 1 && BpodSystem.Status.BeingUsed == 0);
check_chipmunk_replay_session('/tmp/chipmunk-rollout-TIMESTAMP/natural', {'VisualTask'}, '', 3);
check_chipmunk_replay_session('/tmp/chipmunk-rollout-TIMESTAMP/repeated');
check_chipmunk_replay_session('/tmp/chipmunk-rollout-TIMESTAMP/bad-enable', {'VisualTask'}, '', 3, 'invalid');
```

Require all assertions to pass: three saved trials per session, expected replay metadata, no leaked driver timers, closed sound server and Bpod idle. The last test deliberately records failed replay validation while preserving the three completed active trials. It must return normally and save.

These checks use FakeSubject, temporary output/settings and synthetic emulator calibration. They disable cameras and uploads. Leave SpikeGLX host blank. No additional endurance run is needed: the tested workload already exceeded the sub-1,000-trial animal workload.

Before the first live session, restart MATLAB/Bpod in hardware mode. Confirm the intended subject/settings file, half-second base wait, reward volumes, camera selection and manipulation preset with the operator. Replay should remain off unless explicitly requested. Retain existing rig calibration. Check the first short session's MAT and notes before wider use.

For historical comparisons, also match the original port-LED behavior and hold convention. The tested recent Mercury visual settings match the half-second VisualTask path. Original one-second exponential sessions need baseWait=1; older lights-on visual tasks need the corresponding LED-preserving assembler. Legacy assembler names require an explicit settings mapping. See the [historical comparison](audits/unified-task-2026-11-01.md#historical-task-equivalence) before reusing an old settings file.

There is no recording return path from TTL/soundcard/speaker/PWM/LED outputs. Software and camera tests do not measure physical output timing or calibrated levels. Live SpikeGLX acquisition remains a separate hardware check.

## Roll back

End the session normally and close MATLAB/Bpod. Use the recorded backup directory:

```sh
cd '/home/anne/Bpod Local/Protocols/chipmunk_solo'
git status --short
previous=$(cat "$backup/head.txt")
git switch --detach "$previous"
```

If `branch.txt` records a branch and it still points at that same SHA, `git switch BRANCH_NAME` can restore the branch attachment. Do not move a branch that has since advanced. Restart MATLAB to clear loaded task code.

Keep any new session data. Switching code does not require restoring animal settings or calibration. If those were changed and restoration is needed, compare against the backup first and restore only the identified files; preserve the current copies. Retain the full protocol archive for recovery rather than deleting or replacing the checkout wholesale.

## Consolidating existing launchers

The `compat/half_second_chipmunk_solo` and `compat/half_second_chipmunk_ephys` folders preserve the existing Bpod protocol names and subject-settings selections. Each delegates to the sibling `chipmunk_solo` checkout. Their `Experiments` links use the canonical presets. The ephys launcher supplies `jupiter.local` only when the saved host is missing or blank.

Before activating these launchers, back up all three protocol directories, settings and calibration. Replace the legacy directories with links to the matching `compat/` folders only after the candidate has passed real Mercury emulator tests through both entry points. Keep the original directories outside `Protocols` for rollback. Existing session settings and calibration must remain byte-identical. Do not copy synthetic test calibration into the rig calibration directory.

Verify both the native `chipmunk_solo` path and the old launcher names, recording enable/disable, Stop/replay, saved MAT files and the live XIO Digital IO tab. After replacing the active paths, run a fresh emulator checkout against those paths. Close MATLAB before changing paths to avoid cached functions from different versions. Restore all three original directories together if the checkout fails.

## Mercury migration checkpoint — November 1, 2026

The active runtime is candidate `4166631aef14a829ba6627f0e3732efd0dde8428`, installed under `/home/anne/chipmunk-candidates/20261101-225126/chipmunk_solo`. `Protocols/chipmunk_solo` points there; the two old protocol names point to its `compat/` launchers. There is one active implementation, and both old Bpod selections retain their existing subject settings.

Backup: `/home/anne/chipmunk-rollbacks/20261101-225126`. Its `original-protocols/` folder contains all three original directories. Checksummed archives also retain the protocols, all 25 settings files and the configuration/calibration. The original canonical checkout was clean at `bc8095c`; the archived half-second checkout was clean at `0577522`.

Candidate validation passed all 13 configured settings GUI/Update/Save round trips (12 empty placeholders skipped), three legacy-solo emulator trials, six legacy-ephys active trials and three passive replays. The live XIO recording controls and 13 digital/sync lines passed. A fresh deployed-path checkout found all three names in Bpod Launch Manager and passed six more active trials. Independent MAT readback confirmed all 15 active trials and three replays; six XIO binary files matched metadata sizes, complete sample frames and SHA-1 checksums. All 25 live settings files and the calibration remained byte-identical. See [machine-readable evidence](../tests/evidence/mercury-migration-2026-11-01.json). Tests use FakeSubject, isolated session paths and synthetic calibration; they do not alter the rig calibration. Jupiter's normal recording root is `D:/data`, from its local LabData preferences.

### Roll back this deployment

Close MATLAB/Bpod on Mercury and stop acquisition on Jupiter. Run:

```sh
python3 /home/anne/chipmunk-rollbacks/20261101-225126/rollback.py
```

This restores all three original protocol folders together, retaining the candidate checkout and deactivated links. It does not overwrite settings or calibration. Restart MATLAB after rollback. Do not use the earlier single-checkout Git rollback instructions for this three-folder migration.

The migration also backed up MATLAB pathdef.m and removed 118 saved Chipmunk path entries, including archived .git and miniscope subfolders. Bpod adds the selected protocol at launch. The rollback command restores the saved path only if it still matches the migration cleanup, protecting later edits.


## Recording workflow update — November 2, 2026

Mercury now uses runtime `a8d5495d0170fb68c4fccf1644f7acb383ef50d7` at `/home/anne/chipmunk-candidates/20261102-recording/chipmunk_solo`. All three protocol links point into this candidate. The previous candidate remains intact. New rollback: `python3 /home/anne/chipmunk-rollbacks/20261102-recording/rollback.py`, with MATLAB closed. This restores the preceding protocol links; the original migration rollback is also retained.

The Jupiter desktop launcher opens tools without acquisition. On cold launch it makes a verified backup of `daq.ini` and replaces only the saved run name with a unique `Ready_…` placeholder. Bpod then assigns the real session name. A real cold launch verified that no other settings changed and acquisition/recording stayed stopped.

In Bpod, use **Prepare recording**, inspect signals, then **Start session**. Advanced retains manual controls and the intended physical device selection. Device selection is intentionally not fixed to XIO-only in production preferences. The private surgery-plan folder is `/home/anne/chipmunk-anatomy/20261102`; planned overlays require a matching neural probe and are not histology confirmation.

Validation passed two consecutive staged XIO/emulator sessions (six active trials, three passive replays), followed by three saved active trials through the deployed legacy ephys launcher. Recording was confirmed before trials and remained active through requested replay. All 22 settings files present immediately before this update and all four calibration files stayed byte-identical. Three old FakeSubject test settings from the original migration inventory were already absent before this update; no animal settings were missing. Production preferences were restored after tests, with the normal `D:/data` root and private anatomy folder; no test-only device string was retained. MATLAB exited and Jupiter was left idle.

See [workflow evidence](../tests/evidence/recording-workflow-2026-11-02.json) and the native Prepare/Start screenshots in the README. Local lifecycle/failure/ownership, core task, digital input, legacy-launcher and anatomy transform tests passed. Live neural anatomy, probe/headstage acquisition, physical output timing and ephys camera timing remain unverified. Emulator runs emitted ALSA underrun warnings.


## GUI log and session-directory update — November 2, 2026

Runtime `7dfd5bc79c4a933f6cb477a04ba4ab0b056ab00b` at `/home/anne/chipmunk-candidates/20261102-ephys-feedback/chipmunk_solo` replaces the preceding candidate. The three Bpod protocol links use this runtime. Previous candidates remain intact; close MATLAB and run `python3 /home/anne/chipmunk-rollbacks/20261102-ephys-feedback/rollback.py` to restore the preceding links.

The GUI title uses the configured host/port. A timestamped action log replaces the static help below Prepare and is saved as `EphysActionLog`; `EphysRecording` identifies the host, directory and run name. Prepare starts acquisition with recording off. Start session confirms recording before trials. Connection fields are locked while acquisition runs.

Recording files now use `<Jupiter data root>/<subject>/<Bpod session timestamp>/ephys/`, with normal SpikeGLX run subdirectories inside. Bpod files use the same subject/timestamp under Mercury's data root in `chipmunk/`. Mercury-to-Jupiter passwordless SSH was configured with Gabriel's explicit approval, using a dedicated key retained on Mercury and the rig user's SSH host configuration; prior configuration and authorized keys were backed up and preserved. The task stores no passwords. Existing recordings were not moved.

Two staged live XIO/emulator sessions passed six active trials and three passive replays, followed by three trials through the deployed legacy ephys launcher. Saved MAT readback verified session identity, recording directory and complete action logs, including replay and shutdown. Binary size/frame/SHA-1 verification and final rollout details are in [feedback evidence](../tests/evidence/ephys-feedback-2026-11-02.json). Existing settings/calibration were preserved. Production preferences retain `D:/data`, the private anatomy folder and no test-only XIO selection. Native screenshots in the README show the deployed action log. Neural acquisition/anatomy, physical timing and ephys camera timing remain outside this XIO/emulator validation.


## Post-replay console reset — November 2, 2026

Gabriel's real FakeSubject `20261102_091522` session saved eight active trials and all eight requested replays. Its saved action log confirms acquisition/recording stopped, and the recording binary passed size/frame/SHA-1 verification. The reported incomplete finish was a native Bpod console defect: replay calls RunStateMatrix after the operator's Stop; the native runner restores the Pause icon, while the previous cleanup only cleared BeingUsed. The earlier regression checked flags and saved data, missing the stale native control.

The fix runs native RunProtocol Stop in final cleanup, while preserving MATLAB's stopped path, and disables the retained performance window's task button with the short label Finished. The regression now checks the actual GoButton pixels, idle state flags, completion control and saved MAT data. The defective console state was reproduced before the fix. Local repeated, natural-completion and replay-error cases passed afterward. Mercury's deployed legacy ephys launcher passed two active/replay XIO sessions with actual console/control assertions; native completion screenshots are included in the PR.

The fixed runtime is `c0e907f` in `/home/anne/chipmunk-candidates/20261102-replay-console/chipmunk_solo`. All three protocol links point into it. Rollback with MATLAB closed: `python3 /home/anne/chipmunk-rollbacks/20261102-replay-console/rollback.py`. The previous candidate and settings/preferences backup are retained. The original user session was checksum-verified unchanged; all 24 settings and four calibration files present at this rollout were preserved. Production preferences retain D:/data and the private anatomy folder, without test-only devices. The desktop MATLAB process was closed gracefully at Gabriel's explicit request before deployment.

[Console-reset evidence](../tests/evidence/replay-console-reset-2026-11-02.json) records user-session preservation, regression coverage and rig verification. Neural acquisition, physical timing and ephys camera timing remain outside these emulator/XIO checks.


## Venus and Earth rollout — November 2, 2026

Both rigs now run the same fixed task source at `cd65176` from `/home/anne/chipmunk-candidates/20261102-unified/chipmunk_solo`. All three protocol names delegate to that candidate. Each rig retains its own original protocol directories, archives, configuration and calibration under `/home/anne/chipmunk-rollbacks/20261102-unified`; run its `rollback.py` with MATLAB closed to restore the original folders and saved task paths. All 21 existing subject settings and four calibration files per rig stayed byte-identical. Fifteen stale saved task-path entries were removed on each.

Each rig passed ten configured settings GUI/Update/Save checks, six staged active trials with three passive replays, and three further trials through the deployed legacy solo launcher. Native launch-manager discovery, final console state and Finished control passed. Independent saved-MAT readback confirms the nine active trials and three replays per rig. Earth uses the native console Play action (StartPause); its pre-existing convenience RunProtocol('Start') entry references a missing NewLaunchManager, so validation uses the actual GUI action without modifying Bpod software.

Venus alone has dedicated, strictly verified SSH access to Jupiter and the private surgery-plan folder. Its staged ephys/XIO checks completed before Gabriel requested stopping additional integration tests to record real data from Mercury/Jupiter. No further Jupiter commands or ephys tests were issued after confirming the Venus test process had ended and Jupiter was not actively running that test. Venus's final deployed check was behavior-only; normal recording preferences were saved locally with D:/data and no test-only device selection. Earth received no Jupiter routing changes and was tested with ephys off. Mercury/Jupiter acquisition was not stopped or reconfigured during the remaining work.

[Per-rig rollout evidence](../tests/evidence/venus-earth-rollout-2026-11-02.json) contains saved-session hashes and scope. Probe acquisition/anatomy and physical stimulus/camera timing remain unverified. These are software/emulator and Venus XIO checks, not live-animal validation.


## Native ephys/anatomy rollout — November 3, 2026

Mercury now runs `24ace1b945e24b1bec8a51c9f31ec654e076ce2f` from `/home/anne/chipmunk-candidates/20261103-ephys-anatomy/chipmunk_solo`. The canonical and both compatibility protocol links point into this candidate. The preceding replay-console runtime and its preferences remain intact.

Before activation, the last real session's 249 saved trials were verified and the visually idle MATLAB desktop was closed gracefully. Backups retained all 24 subject-settings files, four calibration files, four framework-configuration files and prior links/preferences. Archive contents were compared against the source hashes. With MATLAB closed, the actual rollback restored all three prior links; the candidate was then reactivated. Protected files remained unchanged throughout.

A fresh MATLAB/Bpod emulator discovered all three protocol names and exercised the installed legacy ephys entry point against the isolated Jupiter simulated NP2014 plus live XIO. Two sessions passed six active trials, three completed replays, pre-trial recording confirmation, recording through replay, matching session directories, saved-MAT readback and native Play/Finished console cleanup. Four neural/XIO binaries passed size/frame/SHA-1 checks. Tests used isolated FakeSubject paths and synthetic emulator calibration; no test calibration/settings replaced the real files.

Normal preferences were restored offline to port 4142, `D:/data` and shared `D:/VVASP`, without persisting simulated device selections. MATLAB and the isolated simulator are closed; temporary simulator access was removed and its manual launcher disabled. Jupiter's production command server was subsequently enabled on port 4142 at the user's explicit request. Both the IP address and `jupiter.local` were verified from Mercury; acquisition and recording remained off. The saved enable flag has a verified backup. [Server check](../tests/evidence/jupiter-command-server-2026-11-03.json). The desired Dock 2 addresses must also exist in native Configure Slots. No physical probe/headstage or output/camera timing test was performed, and the original physical-probe crash remains unresolved. Emulator audio underrun warnings occurred.

Rollback, with MATLAB closed:

```sh
python3 /home/anne/chipmunk-rollbacks/20261103-ephys-anatomy/rollback.py
```

This restores the three preceding protocol links and retains the new candidate and test files. It does not overwrite data, subject settings or calibration. [Deployment evidence](../tests/evidence/mercury-ephys-anatomy-rollout-2026-11-03.json).

## Production XIO workflow recheck — November 3, 2026

After a reported error on Prepare, a fresh MATLAB process used the installed runtime and normal production Jupiter server at `jupiter.local:4142`. The actual Prepare button callback passed with the saved `D:/data`, `D:/VVASP` and `(20,obx)` preferences. Two full FakeSubject emulator sessions then passed Initialize, Prepare, Start, six active trials total, three passive replays, MAT readback and console cleanup. Both native XIO binaries passed metadata byte-count, frame and SHA-1 checks. Recording was confirmed before trials and remained enabled through replay. Mercury independently confirmed acquisition and saving off afterward. Four Bpod configuration files and client preferences were restored byte-for-byte; the existing idle desktop was left open.

**The reported failure was not reproduced.** These checks use production SpikeGLX and live XIO, but Bpod is emulated and no physical probe/headstage path was tested. The original desktop error history was not captured. No runtime fix is claimed. See [production workflow evidence](../tests/evidence/production-ephys-workflow-2026-11-03.json).

## Recording failure recovery — November 4, 2026

Mercury is deployed at `db1fee9`, under `/home/anne/chipmunk-candidates/20261104-ephys-recovery/chipmunk_solo`. All three protocol names point to this candidate. Recording loss stops new active trials/replays at their boundaries and saves the failure. Shutdown attempts one reconnect and verifies session identity before stopping; an unconfirmed stop is warned and saved. Lost start acknowledgements are reconciled, host changes clear the folder cache, and camera failures block Start and attempt rollback. Stimulus plot lines now have explicit axes parents; the original code failed the interleaved-redraw regression.

The candidate passed consecutive normal production-XIO sessions, deliberate recording loss during active trials and replay, and failure-focused MATLAB tests. The installed legacy ephys launcher then passed three active trials and three replays. The final camera rollback extension passed its suite from the installed checkout. Five XIO binaries passed size/frame/SHA-1 checks; saved MAT data was independently read back. See [recovery evidence](../tests/evidence/ephys-recovery-2026-11-04.json).

All 24 subject settings, four calibration files, four framework configuration files, original preferences and the latest real session were preserved. A real rollback/reactivation round trip passed. MATLAB is closed, the production command server remains enabled, and acquisition/recording are off. With MATLAB closed, rollback is `python3 /home/anne/chipmunk-rollbacks/20261104-ephys-recovery/rollback.py`.

These fixes do not establish the cause of the original reported Prepare error or physical probe crash. Recording checks run at trial boundaries; physical probe/headstage, camera capture and output timing remain unverified.
