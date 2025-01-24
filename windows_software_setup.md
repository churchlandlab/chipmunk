# Setting Up a Computer for Chipmunk

## UCLA Security Compliance
1. **Install Security Tools**:
   - Install **Sophos**.
   - Run the batch script provided.

2. **Enable BitLocker**:
   - Go to the C drive and attempt to enable BitLocker.
   - If an error occurs regarding compatibility:
     - Open the Group Policy Editor (press `Win + R` and type `gpedit.msc`).
     - Navigate to:
       ```
       Computer Configuration > Administrative Templates > Windows Components > BitLocker Drive Encryption > Operating System Drives
       ```
     - Select **"Require additional authentication at startup"** and enable it.
   - Set the authentication method to a password and save the recovery key to a secure location.
   - Encrypt the used disk space in **New Encryption Mode**.
   - Restart the computer.

3. **Alternative Steps for BitLocker**:
   - If BitLocker still doesn't work, try enabling **"Require additional authentication at startup for Windows"** in the same way.

---

## Initial Computer Setup
1. **Change Computer Name and Create Local User**:
   - Go to **Settings > Accounts > Family**.
   - Create a local admin user account named **Anne** (without a Windows account).

2. **Install Hardware**:
   - Disable all sound devices.
   - Turn off the computer and mount the sound card.
   - Restart and install the corresponding drivers.

---

## Software Installations
1. **Required Software**:
   - MATLAB (with the following toolboxes):
     - Instrument Control Toolbox
     - Statistics and Machine Learning Toolbox
     - Signal Processing Toolbox
   - Git
   - Arduino (ensure compatibility with the Arduino software version).
   - Anaconda (add the Conda Python path during installation).
   - Psychtoolbox
   - MediaSDK
   - Teensyduino

2. **Bpod Setup**:
   - Clone the **Bpod Gen2** repository into the **Documents** folder and run it.
   - It will generate a folder called **Bpod Local**.
   - Create two subfolders in **Bpod Local**:
     - `Protocols`
     - `Data`
   - Clone **Chipmunk** into the `Protocols` folder.
   - Include the WhiteNoise calibration file in the **Calibrations** folder in **Bpod Local**.
   - Run Chipmunk to test.

3. **Camera Software**:
   - Download and install **SpinView (SpinnakerSDK)** from:
     [SpinnakerSDK Installer](https://flir.box.com/v/SpinnakerSDK).
   - Install the corresponding Python packages using `pip`.

---

## Labcams Setup
1. **Install Labcams**:
   - Open GitBash in the **Anne** user folder.
   - Run: `pip install labcams`.

2. **Run Labcams Once**:
   - This will generate a **labcams folder** and a default template file.

3. **Install FFMPEG**:
   - Open the Anaconda prompt and type:
     ```bash
     conda install ffmpeg -c conda-forge
     ```

4. **Configure Labcams**:
   - Use the following parameters:
     - `pxformat`: Mono8
     - `hardware_trigger`: out_line3
     - `recorder_path_format`: `{filename}_{datename}_{nfiles}`
     - `binning`: 2
