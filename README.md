# chipmunk

Freely moving auditory and visual discrimination task for mice (adapted from Raposo et al. 2012)

### Introduction

This repo contains the code, setup description, assembly instructions, and parts design to build a freely moving behavior setup. The task is a visual and/or auditory accumulation of evidence task. The stimuli are stochastic ticks and/or flashes. 

### Setup instructions

You can find a spreadsheet with a parts list [here](hardware_setup/parts_list.xlsx). The designs for custom parts are in **/custom_parts**. 

After getting all the nessary parts, follow these steps:

1. Grab a breadboard big enough to place the behavioral enclosure, cameras, and any other additional equipment you might need. This will depend on the experiments specific needs.
2. Start assembling the behavioral enclosure and make sure there is enough distance between the breadboard and the bottom of the enclosure. This is to make sure that there is enough distance between a camera at the bottom and the bottom of the enclosure to visualize the subject in the experiment.
3. The back piece of the behavioral enclosure has openings for placing nose pokes and an LED board (to deliver experimental visual stimuli). Start by assembling the LED board. To do so, grab two of the LED panels and and place them
	
[This is how a finshed rig looks like.](images/rig.jpg)
	
To build a rig for
	
3d parts for building the setup are in the **custom_parts/enclosure** folder.
	
The walls are laser cut from *pololu* and the drawings are in the **custom_parts/enclosure**
	
The visual and auditory stimuli printed circuit boards are [here](https://github.com/churchlandlab/SpatialSparrow/tree/dev-couto/pcb/led_panel_split) and can be ordered from *SeeedStudio*.

### Behavior monitoring

Cameras wiring for sync is done like this. (Needs diagram.)

Use cameras that have GPIO connections like the FLIR Chamaeleon 3. 
On the Chamaeleon 3 USB you can use the Purple wire (GPIO 2). Connect to BPod to signal trial start and/or end.  To sync multiple cameras use the Green wire and set one of the cameras as master (It is smart to use the same sampling rate). 
	
### Software instalation

#### Bpod gen 2

Install Bpod from the repository [here](https://github.com/sanworks/Bpod_Gen2). This was tested with commit `329bd9e`.

### chipmunk task
Clone the repository to `Bpod Local/Protocols`. If you make changes; create a branch and remember to commit changes regularly.

### Calibration 

##### Stimuli

The visual stimuli LEDs response curve should have a plot here.

The auditory speaker response curves were measured with X microphone and a picture should be here.

This needs to be done for every rig? Stored somewhere? Where?

#### Water reward size

Within the Bpod control panel, click on the wrench icon and select the water spout icon. This will take you to the water calibration panel. From there, select the valves you will calibrate and record at least three measurements (we use 30, 60, and 90ms with 300 repetitions). After calibrating, test curve (we use 4 microliters). Official Bpod documentation [here]([url](https://sites.google.com/site/bpoddocumentation/user-guide/general-concepts/liquid-calibration?pli=1)).




Cameras should be set like the following picture. This gives the tracking results with DeepLabCut below (figure).

### Training strategy

Training has 3 phases:

1. Habituation - description of what happens in this phase. How long it lasts. When it ends.

2. Training phase - during these phase mice do the task but only with easy stimuli. This takes around 4 weeks.

3. Testing/experiment phase - mice are now considered experts and difficult stimuli are introduced. Mice perform X above chance.
	
Figure of performance, accross days. Code to produce this figure in the **notebooks** folder
	

### TODO

Arena size is 20x20cm. An additional chamber can attached to hold an observer.
 
1. walls and floor - laser cut drawings there is an additional 3d part to connect the walls - use transparent red acrylic #2423 from *Pololu*, 6mm. Where can we find small hinges?
2. test the stimuli and put the results in a figure here somewhere. With a description of how to do this.
3. Do we use a sound card?? What the latency? Fixed? How fixed?
4. 3d parts for the ports 2 - adapt the design so that head gear on a mouse is not does not touch the port during licking. Can we do this just with a spout and capacitive sensing?
5. What's in the current port PCB, where the drawing?
6. try different training strategies. Find the best strategy. What the best way to get multimodal enhancement? What is the best loudness and visual saliency? 

Most of these can be done in parallel, some can't. Version 1 can be rough for most of these (we can use code and audio from MudSkipper2 for now.) 


