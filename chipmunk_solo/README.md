# chipmunk_solo

Single-mouse version of [chipmunk](../chipmunk/README.md). Mice hold the center port for `baseWait` (0.5 or 1 s) plus a random extra wait (mean 0.1 s when `minWaitTime` is `exp`), then report the stimulus at a side port.

![Stimuli & performance tab](images/gui/solo-performance.png)

![Task control tab](images/gui/solo-task-control.png)

## Running a session

Use a real subject name or `FakeSubject`. For the emulator, start Bpod with `Bpod('EMU')`. Data goes to the first `local_paths` entry in `~/labdata/user_preferences.json` as `{subject}/{YYYYMMDD_HHMMSS}/chipmunk/` (or the Bpod data folder if that file is missing).

Pick a labcams config at startup, or leave it blank to keep the config of an already-open labcams.

## Stimulus manipulations

Presets in Task control (need `isPoissonStim = 1`):

- **Standard**: normal stimulus
- **Dim**: a percentage of trials at the chosen rates use the dim brightness
- **Long**: a percentage of trials at the chosen rates use 75 ms pulses with a 125 ms minimum interval (rates up to 5 Hz)
- **Equalized**: brightness scaled so rate × brightness is constant

Click Update settings to apply; the change starts on the next trial. Each trial saves the brightness, pulse duration and interval it used. Settings changes are logged per trial in `notes.txt`.

<details>
<summary>Preset controls</summary>

![Standard](images/gui/manipulation-standard.png)
![Dim](images/gui/manipulation-dim.png)
![Long](images/gui/manipulation-long.png)
![Equalized](images/gui/manipulation-equalized.png)

</details>

## Passive replay

Set `passiveReplayEnable` to `1` before pressing Stop. `passiveReplayFraction` sets how many eligible trials to replay and `passiveReplayOrder` sets `sequential` or `random`. Press Stop again to abort.

Each replayed trial plays the stimulus the mouse saw, cut where the trial ended. Trials without a stimulus or with an early withdrawal are skipped. There are no rewards or punishments.

Replay is saved in `SessionData.PassiveReplay` and in `<subject>/<session>/chipmunk_passive/`, which labdata imports as a separate dataset.

## Ephys (optional)

Leave the SpikeGLX host blank for behavior only. Set it (e.g. `jupiter.local`) to record.

1. Open SpikeGLX on Jupiter.
2. Start the protocol, check the probe docks and XIO in **Devices** and click **Prepare recording**.
3. Click **Start session**. Stop saves the behavior, stops the cameras and then stops the recording.

SpikeGLX saves to `<data root>/<subject>/<session>/ephys_g0/` on the recording computer. The rig needs passwordless SSH to it (`ssh -o BatchMode=yes jupiter.local hostname` should work). Settings are saved in `spikeglx_prefs.mat`.

Tabs: **Devices**, **Probe** (AP overview), **Analog** (OneBox inputs), **Digital** (XD0–XD11 and sync) and **Anatomy** (planned probe track from the VVASP surgery plan).

The VVASP folder is set in the Anatomy tab (`D:/VVASP` on Jupiter). Profiles are made with `tools/export_vvasp_anatomy.py`. These are surgery plans, not histology.

![Digital IO tab](docs/screenshots/digital-io.png)

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

## Tests

`tests/run_rig_checks.sh` runs all the checks on a rig. See [testing](docs/testing.md).
