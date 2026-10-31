/*
Teensy code to synchronize the miniscope square pulses (each orientation change indicates
an acquired frame) and the output from a Bpod BNC (set to high at the beginning of 
each trial). Run syncMiniscopeToBpod.py to generate a synchronization log file
(.mscopelog). Frames and trial events are recorded as:
Recording pin, frame/trial number, timestamp (in miliseconds)

This program first reset the frame and trial counts when receiving the serial input
string '1' (= 49). Then incoming frames and trial events will be logged using the
respective interrupts. At the end when string '0' (=48) arrives the output of the
will be interrupted.
LO, 8/5/2021
*/

#define MINISCOPE 2
#define BPOD 23

// Set up the required variables
volatile unsigned long frameNumber = 0; //Counts the number of frames acquired from the miniscope
volatile unsigned long long timeStamp = 0; //Assigns a timestamp in milisceonds from the start of the
//acquired frame from the miniscope or the trial event.
volatile bool trialStartFlag = 0; //Flag for trial start versus stop
volatile unsigned long trialNumber = 0; //Count trial number
volatile bool initialized = 0; //Jumps to true once the frames have been reset and the header is sent
int serialMessage = -1; //Message from the python function to enable counting or stoppining it.


void setup() {
  Serial.begin(9600);

  pinMode(MINISCOPE, INPUT);
  pinMode(BPOD, INPUT);

  //Set the interrupts
  attachInterrupt(digitalPinToInterrupt(MINISCOPE), miniscopeFrame, CHANGE);
  //Use digitalPinToInterrupt for compatibility with other arduino devices
  attachInterrupt(digitalPinToInterrupt(BPOD), BpodTrialEvent, CHANGE);
  }

///--------Leave empty for experiment, uncomment for checking------///
void loop() {
}

///-------Interrup function for miniscope frame capturing and serial output-----------///
void miniscopeFrame(){
  if (initialized){
    frameNumber++; //Add this frame to the number log
    timeStamp = millis(); //Get a timestamp for the incoming frame
    Serial.printf("%d,%lu,%llu\n", MINISCOPE, frameNumber, timeStamp);
  }
}

///-----Interrupt function for Bpod trial event info------///
void BpodTrialEvent(){
  if (initialized){
    timeStamp = millis(); //Get the time stamp for the trial event
    trialStartFlag = trialStartFlag == 0; //Switch the state of the logic variable
    if (trialStartFlag) {
      trialNumber++; //If this is a trial start go to the next trial number
      Serial.printf("%d,%lu,%llu\n",BPOD, trialNumber, timeStamp);
    //} else {
   //  Serial.printf("# %lu,%llu - trial_end: %lu\n",frameNumber, timeStamp, trialNumber);
    }
  }
}

///------Get instructions from syncMiniscopeToBpod.py---------///
void serialEvent() {
  serialMessage = Serial.read();

  //Reset the trial variables when a serial input arrives
  if (serialMessage == 49) {
  frameNumber = 0;
  timeStamp = 0;
  trialNumber = 0;
  trialStartFlag = 0;

  //Write the pin specs to the header
  Serial.printf("Reset frame and trial count. Miniscope channels is: %d and Bpod channel is: %d\n", MINISCOPE, BPOD);
  Serial.println("channel, eventNumber, teensyTime"); //println automatically inserts a line break at the end of the string
  initialized = 1;
  } else if (serialMessage == 48) {
    initialized = 0;
  }
}
