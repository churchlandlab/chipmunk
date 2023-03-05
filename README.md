# chipmunk

Freely moving auditory and visual discrimination task for mice (adapted from Raposo et al. 2012)

### Introduction

This repo contains the code, setup description, assembly instructions, and parts design to build a freely moving behavior setup. The task is a visual and/or auditory accumulation of evidence task. The stimuli are stochastic ticks and/or flashes. 

### Setup instructions

You can find a spreadsheet with a parts list [here](hardware_setup/parts_list.xlsx). The designs for custom parts are in **/custom_parts**. If you have any doubts about how a certain part is supposed to look like refer to [this image of a finished setup](images/rig.jpg)

Here is a **condensed** step-by-step for building the setup:

1. Assemble enclosure onto a breadboard.
2. Assemble the LED panel.
3. Assemble the nose pokes.
4. Wire the cameras together and place in breadboard.
5. Assemble water delivery system. 

Here is a **detailed** description for building the setup:

1. Grab a breadboard big enough to place the behavioral enclosure, cameras, and any other additional equipment you might need. This will depend on the experiments specific needs.
2. Start assembling the behavioral enclosure and make sure there is enough distance between the breadboard and the bottom of the enclosure. This is to make sure that there is enough distance between a camera at the bottom and the bottom of the enclosure to visualize the subject in the experiment.
3. The back piece of the behavioral enclosure has openings for placing nose pokes and an LED board (to deliver experimental visual stimuli). Start by taking two rectangular pieces of acrylic, one of them being white and semi-transparent (the color and property of the other does not matter). You will now need to make four holes on the corners of each piece. Make sure these holes are aligned between the two rectangles since you will need to drive screws through both holes later on.
4. To assemble the LED board, grab the ALA LED flashboard and connect a second LED array to it. Fix the LED arrays on the non-white rectangular piece of acrylic. Then, take the white acrylic piece and make sure it fits in the rectangular opening on the back wall for the behavioral enclosure. Glue the white acrylic in place on the back wall. Now, join the two acrylic pieces (white piece glued to back wall and additional piece with the LED arrays) by threading a screw between the two pieces. Make sure to use spacers so that there is a space between the LED arrays and the back wall (this will allow for more light diffusion across the white piece).
5. To assemble the nose pokes, follow the instructions listed on **/hardware_setup/nose_poke_instructions.docx**.
6. To wire the cameras, follow the instructions found on https://github.com/jcouto/labcams/blob/main/camera_instructions.md.
7. To assemble the water delivery system, grab the solenoid valves and attach silicone tubing to two of the three protrusions (cover the third one with a black cap). One of the ends goes into a 50 mL syringe that will contain the liquid being delivered in the experiment (water in this case).

	
To build a rig for9	
3d parts for buildi0ng the setup are in the **custom_parts/enclosure** folder.
	
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


