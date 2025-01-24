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
     - **Warning**: Ensure the Arduino version is compatible with Teensyduino. This is critical for proper functionality.
     - Download and install the latest version of the Arduino IDE from the [official Arduino website](https://www.arduino.cc/en/software).
   - **Teensyduino**:
     - Install Teensyduino, ensuring its version matches the Arduino IDE version.
     - Follow installation instructions for Linux from the [Teensyduino website](https://www.pjrc.com/teensy/td_download.html).
   - **Anaconda**:
     - Download and install Anaconda:
       ```bash
       wget https://repo.anaconda.com/archive/Anaconda3-latest-Linux-x86_64.sh
       bash Anaconda3-latest-Linux-x86_64.sh
       ```
     - Add Conda Python to the PATH during installation.
   - **Psychtoolbox**:
     - [Psychtoolbox website](http://psychtoolbox.org/download)

2. **Bpod Setup**:
   - Clone the **Bpod Gen2** repository:
     ```bash
     git clone https://github.com/sanworks/Bpod_Gen2.git ~/Documents/Bpod_Gen2
     cd ~/Documents/Bpod_Gen2
     ```
   - Create two subfolders in the `Bpod Local` directory:
     ```bash
     mkdir ~/Documents/Bpod_Gen2/Bpod_Local/Protocols
     mkdir ~/Documents/Bpod_Gen2/Bpod_Local/Data
     ```
   - Clone the **Chipmunk** repository into the `Protocols` folder:
     ```bash
     git clone https://github.com/your-org/Chipmunk.git ~/Documents/Bpod_Gen2/Bpod_Local/Protocols
     ```
   - Place the WhiteNoise calibration file in the `Calibrations` folder:
     ```bash
     mkdir ~/Documents/Bpod_Gen2/Bpod_Local/Calibrations
     cp path_to_calibration_file ~/Documents/Bpod_Gen2/Bpod_Local/Calibrations
     ```
   - Run **Chipmunk** to test.

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
   - Open a terminal in the **anne** user's home directory.
   - Run:
     ```bash
     pip install labcams
     ```

2. **Run Labcams**:
   - Run Labcams once to generate the folder structure and a default template file:
     ```bash
     labcams
     ```

3. **Install FFMPEG**:
   - Install FFMPEG via Conda:
     ```bash
     conda install ffmpeg -c conda-forge
     ```

4. **Configure Labcams**:
   - Update the configuration with the following parameters:
     - `pxformat`: Mono8
     - `hardware_trigger`: out_line3
     - `recorder_path_format`: `{filename}_{datename}_{nfiles}`
     - `binning`: 2
