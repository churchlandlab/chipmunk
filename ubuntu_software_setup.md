# Setting Up a Computer for Chipmunk on Ubuntu

## Initial Computer Setup
1. **Create a Local User**:
   - Create a local user named **anne**:
     ```bash
     sudo adduser anne
     sudo usermod -aG sudo anne
     ```

2. **Sound Card Setup**:
   - Disable onboard sound devices if not needed.
   - Install drivers for the sound card:
     ```bash
     sudo apt-get update
     sudo apt-get install alsa-tools
     ```
   - Use `alsamixer` to configure sound settings.

---

## Software Installations

Mercury, venus, and earth are the behavior computers, and **anne** is the account that runs the task. They were left on the versions already installed there. A new behavior computer follows **earth**, the last rig that was set up. `hodgkin` has MATLAB R2025b Update 4 and is not a behavior machine.

- **MATLAB R2022b Update 8** (9.13.0.2502115), with the Instrument Control, Statistics and Machine Learning, and Signal Processing toolboxes
- **Bpod 1.8.0**, at `/home/anne/Bpod_Gen2`. `BpodSoftwareVersion.m` reads `1.80`. The copy on earth is not a git checkout; `Bpod.m` and the version file are both dated 2024-03-01. Copy that directory. Calibration stays in `Bpod Local/Calibration Files`, which this Bpod still uses.
- **Arduino IDE 1.8.19**, with `/usr/local/bin/arduino` pointing at `~/Downloads/arduino-1.8.19-linux64/arduino-1.8.19/arduino`
- **Teensyduino** in that Arduino tree, `hardware/teensy`. The tree does not record a release number. Copy earth's directory rather than installing a newer Teensyduino.
- **Psychtoolbox 3.0.19** (17 February 2023)

Read on 2026-10-31:

| | mercury | venus | earth |
| --- | --- | --- | --- |
| MATLAB | R2022b Update 1 | R2023a | matches |
| Bpod | 1.71, commit `718592d` | 1.72, commit `91a318c` | matches (1.80, no git commit) |
| Arduino IDE | matches | launches 1.8.13 | matches |
| Teensyduino | installed in the 1.8.19 IDE | different core, inside the 1.8.13 IDE, plus a `1.57.2` board package | matches |
| Psychtoolbox | 3.0.18 | matches | matches |

1. **Required Software**:
   - **MATLAB R2022b Update 8**, with these toolboxes:
     - Instrument Control Toolbox
     - Statistics and Machine Learning Toolbox
     - Signal Processing Toolbox
   - **Git**:
     ```bash
     sudo apt-get install git
     ```
   - **Arduino IDE 1.8.19**, from the [official Arduino website](https://www.arduino.cc/en/software). `/usr/local/bin/arduino` should point at that install, as it does on earth.
   - **Teensyduino**, copied from earth's `hardware/teensy` directory. Venus already has an Arduino 1.8.19 download and does not launch it.
   - **Psychtoolbox 3.0.19**:
     - [Psychtoolbox website](http://psychtoolbox.org/download)

2. **Bpod Setup**:
   - Copy `/home/anne/Bpod_Gen2` from earth. That is Bpod 1.8.0 (`BpodSoftwareVersion` 1.80, files dated 2024-03-01). It is not a git commit.
   - Clone this repository to `/home/anne/Bpod Local/Protocols/half_second_chipmunk_solo`. The folder name has to match `half_second_chipmunk_solo.m`. Labcams lives at `/home/anne/labcams`. If you make changes, create a branch and remember to commit changes regularly.

3. **Camera Software**:
   - Download and install **SpinView (SpinnakerSDK)**:
     - Obtain the installer from [SpinnakerSDK](https://flir.app.boxcn.net/v/SpinnakerSDK/folder/73501875299).
     - Follow the Linux installation instructions provided in the package.
   - Install the required Python packages:
     ```bash
     pip install spinnaker-python
     ```

---

## Labcams Setup
1. **Install Labcams**:
   Instructions are found [here](https://github.com/jcouto/labcams?tab=readme-ov-file#instalation-on-ubuntu-2004).

2. **Configure Labcams**:
   - Update the configuration with the following parameters:
        ```
         {
       "cams": [
           {
         "Save": true,
         "serial": CHANGE_ME_TO_CAMERA_SERIAL_NUMBER,
         "driver": "PointGrey",
         "frame_rate": 80.0,
         "gain": 12,
   	    "exposure":12000,
   	    "gamma":1.8,
   	    "binning":2,
   	    "cam_id": 0,
         "pxformat": "Mono8",
         "name": "CAM_NAME",
   	    "recorder":{
   		      "format":"ffmpeg",
             "compression": "27:5M",
   		      "hwaccel":"nvidia"},
   	    "hardware_trigger":"out_line3"
           }
       ],
       "recorder_frames_per_file": 0,
       "recorder_path": "/home/anne/data",
       "recorder_path_format":"{filename}_{dataname}_{nfiles}",
       "recorder_sleep_time": 0.05,
       "server":"udp",
       "server_port": 9999
      }
        ```
