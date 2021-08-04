#include "TimeLib.h"

#define MINISCOPE 3
#define BPOD 6

// Set up the required variables
volatile double frameNumber = 0;
volatile double timeStamp = 0;
volatile bool BpodFlag = 0;

void setup() {
Serial.begin(9600);

//Configure pins
 pinMode(MINISCOPE, INPUT);

//Set the interrupts
attachInterrupt(digitalPinToInterrupt(MINISCOPE), miniscopeFrame, CHANGE);
//Use digitalPinToInterrupt for compatibility with other arduino devices
}


void loop() {
//Serial.write('1');
//delay(500);
}

//The interrup function for miniscope frame capturing
void miniscopeFrame(){

frameNumber++; //Add this frame to the number log
timeStamp = now(); //Get a timestamp for the incoming frame
if (!BpodFlag) {
  Serial.println(frameNumber);
  Serial.println(timeStamp);
 // Serial.write(sprintf('# %d,%d',frameNumber, timeStamp)
}
BpodFlag = 0; //Reset the Bpod flag to false

}
