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
1. **Required Software**:
   - **MATLAB**:
     - Install MATLAB and the necessary toolboxes:
       - Instrument Control Toolbox
       - Statistics and Machine Learning Toolbox
       - Signal Processing Toolbox
   - **Git**:
     ```bash
     sudo apt-get install git
     ```
   - **Arduino**:
     - Install `v1.18.19` from the [official Arduino website](https://www.arduino.cc/en/software).
   - **Teensyduino**:
     - Install `v1.59` and follow installation instructions for Linux from the [Teensyduino website](https://www.pjrc.com/teensy/td_download.html).
   - **Psychtoolbox**:
     - [Psychtoolbox website](http://psychtoolbox.org/download)

2. **Bpod Setup**:
   - Install Bpod `v1.72` from the repository [here](https://github.com/sanworks/Bpod_Gen2). This is what will be used to control everything related to the experiment. 
   - Clone this repository to `Bpod Local/Protocols` on the computer you will be using for running experiments. If you make changes, create a branch and remember to commit changes regularly.

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

4. **Configure Labcams**:
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
