# chipmunk_solo

Freely moving auditory and visual discrimination task for mice (adapted from Raposo et al. 2012). *chipmunk_solo* is an adaptation of the original [*chipmunk*](../chipmunk/README.md) protocol in this repository.

## Introduction

This folder contains the Solo protocol: its code, setup description and assembly instructions. Parts designs are in the repository's [custom_parts](../custom_parts). The task is a visual and/or auditory accumulation of evidence task. The stimuli are stochastic ticks and/or flashes. `baseWait`, in the Experiment panel, is 0.5 s (the default) or 1 s. With `minWaitTime` set to `exp`, the mouse holds the center port for `baseWait` plus a random extra wait that averages 0.1 s. The `minWaitTime` staircase stops at `baseWait + 0.1`.

## Task window

Screenshots captured on Mercury. The performance view replays GRB006 `20240723_142451`: 831 trials, including 397 completed choices. The outcome panel shows the 200 most recent trials; the performance and psychometric plots use the full session. The Task control view uses saved FakeSubject test settings.

The **Stimuli & performance** tab shows the stimulus, outcomes, performance and psychometric plots. The psychometric legend follows the three modality curves.

![Solo performance tab replaying GRB006's July 23 session with 200 recent outcomes and full-session performance curves](images/gui/solo-performance.png)

The **Task control** tab contains the state diagram, `baseWait`, fixation timing and trial delays.

![Solo task control tab with baseWait and timing settings](images/gui/solo-task-control.png)

## Using the task

### Starting a session

Use a real subject name or `FakeSubject`. `Virtual` and `Dummy` are rejected before devices start; those names do not enable emulation. Use `Bpod('EMU')` separately for emulation. Closing the initialization window cancels startup and returns Bpod to idle. Session files are written under the first `local_paths` entry in `$HOME/labdata/user_preferences.json` as `{subject}/{YYYYMMDD_HHMMSS}/chipmunk/`. If that file is missing, the Bpod data folder is used.

The selected labcams JSON is passed to the installed CLI as one quoted file argument. An explicit config restarts an already-open labcams app before recording so the selection actually takes effect. Leave the config blank to reuse an already-open app's current configuration. Startup retains the saved config selection; Cancel in the file picker leaves it unchanged.

### Stimulus manipulation and settings notes

The Task control panel has four presets. Standard retains the normal stimulus. Dim flashes selects the entered percentage of eligible rates and uses the dim brightness without changing the session's normal brightness. Long pulses selects eligible trials and uses the 75 ms pulse / 125 ms minimum interval combination; rates above its 5 Hz capacity retain normal pulses. Equalized luminance scales brightness by the lowest configured positive rate divided by the trial rate. This equalizes rate × brightness in the control values; physical luminance still requires calibration.

Manipulation presets require the Poisson generator (`isPoissonStim = 1`). Normal pulse and gap values are displayed read-only. Dim exposes eligible rates, trial percentage and dim brightness; Long exposes eligible rates, trial percentage and the supported pulse/gap combination. Standard and Equalized disable controls they do not use. Switching the menu does not change an already prepared trial: click Update settings, and the change takes effect when the next trial is prepared. Save settings also requests an update and retains the configuration for future sessions.

Each completed trial saves the effective values in `StimulusBrightness`, `StimulusDuration` and `MinInterval`, in seconds for the duration fields. `TrialSettings(trial).stimBrightness` also retains the effective brightness used for reconstruction. The session baseline is preserved. Settings changes are recorded in `SettingsNotes` at the trial where they take effect, merged with notebook text in `Notes`, and written to `notes.txt` at shutdown. Trials without notes are omitted. These lines describe configuration changes, not observed mouse behavior.

### Current manipulation controls

Real MATLAB/Bpod emulator captures from Mercury, using FakeSubject. These show the added controls; they are not drawings. Selection and Update callbacks were exercised in the full-session test. Short replay labels and a wider order field keep the new controls readable at the normal window size.

<details>
<summary>Standard, Dim, Long and Equalized controls</summary>

Standard leaves manipulation controls disabled.

![Standard preset](images/gui/manipulation-standard.png)

Dim enables eligible rates, trial percentage and dim brightness.

![Dim preset](images/gui/manipulation-dim.png)

Long enables eligible rates, trial percentage and the supported pulse/gap pair.

![Long preset](images/gui/manipulation-long.png)

Equalized uses the configured rates and baseline brightness; unused controls remain disabled.

![Equalized preset](images/gui/manipulation-equalized.png)

</details>

### Passive replay

Replay is off by default. In Task control, set `passiveReplayEnable` to `1` before pressing Bpod Stop. `passiveReplayFraction` selects a fraction of eligible trials, rounded to the nearest trial; `passiveReplayOrder` is `sequential` or `random`. Stop reads these controls even without Update. A second Stop aborts replay.

Replay reconstructs each source trial's stimulus train from its saved settings and intervals, then stops it where the task stopped it: at reward, wrong choice or no choice. Replay therefore plays what the mouse saw, including any repeats from `ExtraStimulusDuration` that it saw before its choice. Trials that never reached `PlayStimulus` or that ended in `DemonEarlyWithdrawal` are excluded. An interrupted active trial can have a shorter actual exposure than its reconstructed train. Auditory noise samples are regenerated. Replay has no port requirements, rewards or punishments.

Saved `SessionData.PassiveReplay` contains source trial numbers, requested and completed counts, per-attempt status, durations, ITIs, modalities, raw events and their state-name mapping. When at least one trial was requested, the same struct is also saved as `PassiveReplay` in `<subject>/<session>/chipmunk_passive/<task file name>.mat`, and the upload prompt sends that folder after `chipmunk/`. labdata stores it as a separate `passive-stimulation` dataset. The task file keeps the struct because it holds the Bpod clock and all sync pulses, task and replay. Abort and error outcomes retain partial results; active trial arrays remain separate. After replay and saving, the native Bpod console returns to its launch icon and the retained performance window shows a disabled **Finished** button. The final reset also runs if replay or teardown fails. The session test checks native console controls as well as running flags and saved data.

### Optional ephys

Leave SpikeGLX host blank for a normal behavior session. Fill it (for example `jupiter.local`) to enable recording controls and hardware-triggered cameras. Port defaults to 4142. The SpikeGLX run name is `ephys`; its normal first recording group is `ephys_g0`. Subject and Bpod session identity belong in the parent folders. Neuropixels files stay on Jupiter; Stop disables recording and stops acquisition before `labdata put` of the Bpod folder.

1. On Jupiter, open **Chipmunk recording tools**. It opens SpikeGLX and checks its command server, leaving acquisition stopped.
2. Initialize the Bpod protocol. In **Devices**, check the probe port/dock rows and **XIO** streams you want to record, or keep **Use current SpikeGLX selection**. Click **Prepare recording** to apply changed or unvalidated device selections using Detect / Verify | Save. An unchanged, validated live selection is reused. Acquisition then starts with recording off.
3. Click **Start session** in the task window. Bpod confirms ephys recording is on, starts configured camera writing, then begins trials. Stop saves a checkpoint of the task data, keeps recording through any requested passive replay, saves the final behavioral data, stops cameras and closes sound, then stops SpikeGLX recording/acquisition last. Shutdown diagnostics are persisted afterward, before the upload prompt.

The **Devices** table shows a Record checkbox, slot, port and dock for each address. Editing a row switches from the current SpikeGLX setup to an explicit selection. XIO is independent of the probe docks; checking it alone records OneBox inputs without neural data. Addresses must first exist in SpikeGLX’s Configure Slots catalog, including both docks if you use Dock 2. Prepare rejects an empty explicit selection; invalid/missing hardware is reported by Detect. Selection is locked during acquisition. The **Advanced** tab retains manual recording controls. An unrelated active run is left untouched. Host, port, data root, devices and anatomy directory are saved in `spikeglx_prefs.mat`.

The title follows the configured host and TCP port. The status separates the SpikeGLX network connection from acquisition and recording; a network connection is not proof that a probe is attached. Probe detection happens during Prepare. The software/API version is available as a status tooltip. Optional surgery-plan overlay status lives in Advanced. The timestamped action log below Prepare records connection, destination, device validation, recording changes, replay and failures. Its final contents are saved as `SessionData.EphysActionLog`; `EphysRecording` records the host, directory and run name. A failed connection is closed and background polling stops contacting it; use **Advanced → Connect** after resolving the recording host’s error. Connection loss does not prove the remote acquisition stopped. The vendored SDK has a two-second initial TCP preflight and does not automatically reconnect an existing socket during a status poll. Normal polling does not add log entries.

**Data root** is the recording computer's root, such as `D:/data`. Bpod creates `<root>/<subject>/<Bpod session timestamp>/` before preparation. SpikeGLX then creates its native `ephys_g0/` recording group there, beside Bpod's `chipmunk/` folder when the session is copied to Hodgkin. Recording a new group manually can advance the native suffix to `ephys_g1`, etc. Ownership checks use both the run name and recording session directory. Existing recordings are not moved. A folder-creation failure blocks acquisition. On Mercury, passwordless SSH to the configured Windows recording host is required; account and key selection live in the rig user's SSH configuration, outside the task repository. Verify the route with `ssh -o BatchMode=yes jupiter.local hostname` after setup.

The Jupiter launcher is in `rig/jupiter/Start-ChipmunkTools.ps1`, with paths configured in `rig-tools.json` using the adjacent example. On a cold launch only, it backs up `_Configs/daq.ini` and changes only `snsRunName` to a unique `Ready_…` placeholder. SpikeGLX validates its saved name before Bpod can assign the real session name; this avoids collisions with an existing recording. It leaves an open SpikeGLX instance unchanged and never starts acquisition. Configure the SpikeGLX command server on the LAN address before use.

#### Recording tabs

- **Devices:** select the probe port/dock and independent OneBox XIO streams, or retain the current native SpikeGLX selection. Checkboxes request acquisition; they are not connection indicators. Addresses must exist in Configure Slots. Slot 20 is a OneBox address; SIM slots 40/41 appear only when that setup includes simulated probes.
- **Neural:** a rolling 0.3 s AP-channel overview, refreshed about twice per second and downsampled to about 1 kHz for display. Per-channel median removal and standard-deviation scaling make contrast relative; this is not a calibrated microvolt or spike-quality plot. Native SpikeGLX settings determine what is saved.
- **OneBox analog:** acquired analog inputs from the first OneBox, vertically offset and scaled for display. It does not configure inputs or change recording.
- **Digital IO:** acquired XD0–XD11 and sync SY6 as low/high traces, retaining full sample resolution within each 0.3 s snippet. This is a periodically refreshed monitor, not a continuous event audit.
- **Anatomy:** preview the selected mouse’s source-verified surgery plan before acquisition, as colored atlas-region bands along four shanks. Distances run upward from the probe tip; a dashed 2,500 µm line marks the requested bank reference on each shank. This display marker does not change the IMRO channel/bank selection. Click a band for its region/range. Reload plan refreshes the source while acquisition is stopped. Previewing never starts acquisition or applies labels; Prepare applies compatible labels to SpikeGLX.
- **Advanced:** reconnect to the network command server; manually enable/disable recording or stop this Bpod session's acquisition. Disable recording keeps acquisition on; Stop acquisition ends both. The surgery-plan folder supplies optional native SpikeGLX shank labels, not probe detection or measured anatomy. Switching tabs never starts or stops recording. Closing this window leaves acquisition alone; normal task shutdown owns cleanup.

#### Surgery-plan anatomy

Set **VVASP folder on host** in Advanced to the shared recording-host folder, normally `D:/VVASP` on Jupiter. `experiments/` contains the original VVASP JSON records; `anatomy/` contains the corresponding atlas-derived profiles generated by `tools/export_vvasp_anatomy.py`. The Anatomy tab reads the selected subject's files over the existing SSH route before acquisition; Prepare reads them again and verifies the source JSON SHA-256 before applying any labels. Changed source records require regenerated profiles; stale labels are rejected. The shared records and generated profiles stay private and outside this repository. Previously exported local profile directories remain supported, and the old standard Mercury anatomy directory preference migrates to `D:/VVASP`.

VVASP supplies planned coordinates, while the exporter uses the matching BrainGlobe atlas to derive region boundaries. Prepare applies those regions through SpikeGLX's native anatomy API for exactly one supported four-shank NP2 probe. Bpod saves the source host, directory and generation provenance; SpikeGLX metadata retains the source filename/hash. A missing, stale or incompatible plan is shown in Advanced and does not block recording. `check_shared_vvasp` tests paired-source validation and stale/unsafe record rejection.

These overlays represent planned surgery coordinates, not histology-confirmed probe tracks. They require no manipulator or Pinpoint application. Keep subject profiles outside the public repository.

The signal-monitoring tabs are Neural, OneBox analog and Digital IO. Digital IO displays all 12 acquired OneBox input bits (XD0–XD11) and the sync input (SY bit 6) as individual low/high traces, at the acquisition sample rate. It monitors acquired channels even when only a subset is saved. These are input readbacks, not output-command telemetry.

![Native Digital IO tab during a live OneBox test](docs/screenshots/digital-io.png)

### Existing rig launchers

`compat/` preserves the `half_second_chipmunk_solo` and `half_second_chipmunk_ephys` Bpod protocol names as thin launchers for this runner. Existing subject settings stay in their original protocol folders. The ephys launcher defaults a missing/blank SpikeGLX host to `jupiter.local` and preserves an explicitly configured host; the solo launcher keeps recording opt-in. Both use the shared experiment presets. They do not load the archived task's Functions folder. `check_legacy_launchers` checks delegation and settings preservation.

## Setup instructions

You can find a spreadsheet with a parts list [here](../hardware_setup/parts_list.xlsx). The designs for custom parts are in [`custom_parts`](../custom_parts). If you have any doubts about how a certain part is supposed to look like refer to [this image of a finished setup](images/rig.jpg)

### A **condensed** step-by-step for building the setup:

1. Assemble enclosure onto a breadboard.
2. Assemble the LED panel.
3. Assemble the nose pokes.
4. Wire the cameras together and place in breadboard.
5. Assemble water delivery system. 

### A **detailed** description for building the setup:

1. Grab a breadboard big enough to place the behavioral enclosure, cameras, and any other additional equipment you might need. This will depend on the experiments specific needs.
2. Start assembling the behavioral enclosure and make sure there is enough distance between the breadboard and the bottom of the enclosure. This is to make sure that there is enough distance between a camera at the bottom and the bottom of the enclosure to visualize the subject in the experiment.
3. The back piece of the behavioral enclosure has openings for placing nose pokes and an LED board (to deliver experimental visual stimuli). Start by taking two rectangular pieces of acrylic, one of them being white and semi-transparent (the color and property of the other does not matter). You will now need to make four holes on the corners of each piece. Make sure these holes are aligned between the two rectangles since you will need to drive screws through both holes later on.
4. To assemble the LED board, grab the ALA LED flashboard and connect a second LED array to it. Fix the LED arrays on the non-white rectangular piece of acrylic. Then, take the white acrylic piece and make sure it fits in the rectangular opening on the back wall for the behavioral enclosure. Glue the white acrylic in place on the back wall. Now, join the two acrylic pieces (white piece glued to back wall and additional piece with the LED arrays) by threading a screw between the two pieces. Make sure to use spacers so that there is a space between the LED arrays and the back wall (this will allow for more light diffusion across the white piece).
5. To assemble the nose pokes, follow the instructions in [`hardware_setup/nose_poke_instructions.docx`](../hardware_setup/nose_poke_instructions.docx).
6. To wire the cameras, follow the instructions found on https://github.com/jcouto/labcams/blob/main/camera_instructions.md.
7. To assemble the water delivery system, grab the solenoid valves and attach silicone tubing to two of the three protrusions (cover the third one with a black cap). One of the ends goes into a 50 mL syringe that will contain the liquid being delivered in the experiment (water in this case). The other end needs to go into a tapered needle that will be threaded through the nose poke to deliver the liquid in the syringe. Fix the syringes at an elevation where gravity can help the water travel since it's a purely passive system (the valve just opens and closes). You can take the valves and adhere them with tape or another type of removable adhesive to a something (leftover acrylic, etc.) that can help them stay in place and not be moving around or floating in the air. **Note: the water delivery system needs to be calibrated before experiments can begin. More on that later.**

### Additional details on purchasing equipment:	

- The walls are laser cut from [*pololu*](https://www.pololu.com/product/749).
- The designs for the visual and auditory stimuli PCBs (printed circuit boards) are found [here](https://github.com/churchlandlab/SpatialSparrow/tree/dev-couto/pcb/led_panel_split) and can be made through [*SeeedStudio*](https://www.seeedstudio.com).

### Camera usage details:

Use cameras that have GPIO connections like the FLIR Chamaeleon 3. On the Chamaeleon 3 you can use the purple wire (GPIO 2) for syncing the cameras. This will be necessary to receive TTL pulses from *Bpod* (more on this later) signaling the start and end of a trial on the camera's log file (see [labcams](https://bitbucket.org/jpcouto/labcams) for using the cameras in your experiments). 
	
## Software installation

Refer to the [Ubuntu software setup](ubuntu_software_setup.md).

### Calibration 

#### Sensory stimuli
Instructions for calibrating the sensory stimuli are pending.

#### Liquid delivery
Within the Bpod control panel, click on the wrench icon, and select the water spout icon. This will take you to the water calibration panel. From there, select the valves you will calibrate and record at least three measurements (we use 30, 60, and 90ms with 300 repetitions). After calibrating, test curve (we use 4 microliters). You can also refer to the [official Bpod documentation](https://sites.google.com/site/bpoddocumentation/user-guide/general-concepts/liquid-calibration) on how to do this.

## Training strategy

A full training guide is available [here](https://grojasbowe.notion.site/Chipmunk-task-training-guide-ebe81437f5f14483b646d6c6ad3185f8).

By Lukas Oesch and Gabriel Rojas Bowe, circa 2024.

## Testing and validation

MATLAB checks live in [`tests/`](tests) and run from this folder (`addpath('tests')`). `tests/run_rig_checks.sh` runs them all on a rig in one command. The [testing guide](docs/testing.md) lists each check, how to run it and what it does not establish; [`tests/evidence/`](tests/evidence) holds the recorded validation runs.
