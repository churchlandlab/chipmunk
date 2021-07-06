//Use serial connection to send byte-encoded information between Bpod and Teensy.
//Incoming bytes are processed on pin 0 and outgoing ones on pin 1. All the other pins are freely configurable.
//Once programmed, Teensy can be supplied with power via the ethernet connection.
//
//This code lets Teensy report beam breaks as events to Bpod. In parallel Bpod can request to start counting
//beam breaks until it receives a stop signal and reports the number of beam breaks that occured during
//the counting period.

// Include the Teensy shield code
#include "ArCOM.h"

// Serial-write variables
unsigned long FirmwareVersion = 2;
char moduleName[] = "ObserverDeck"; // Name of module for manual override UI and state machine assembler
ArCOM Serial1COM(Serial1); // UART serial port

#define START_COUNTING 30 // Define the serial input messages for different bytes
#define STOP_COUNTING 31
#define REPORT_COUNT 32
#define SEND_MODULE_INFO 255

#define BEAM_BROKEN 1 // Define the serial output messages for different bytes
#define BEAM_JOINED 2
#define OBSERVER_FIXATION_SUCCESS 3
#define OBSERVER_FIXATION_FAIL 4
#define UNDEFINED_INPUT_SENT 15

//---------Pin configuration--------------------//

#define BeamBreakReadoutPin 14 // Lets Teensy read from this pin

//----------Set up the serial sampling and pin mode-------//
void setup() {
  //Set the refreshing frequency
  Serial1.begin(1312500); // ethernet baud rate from Bpod
  Serial.begin(9600); // USB baud rate
  
  //Configure pin
  pinMode(BeamBreakReadoutPin, INPUT_PULLDOWN);
  // This pin has to be set to PULLDOWN because it would accumulate charges otherwise and 
  // not report the beam breaks anymore after the first one. Due to the PULLDOWN the input voltage
  // should be a bit higher. Here, rather than the 3.3 V power pin the direct USB/Ethernet 
  // power source is used that comes at ~5 V.
  }

  // Set up the communication variables
  int nBytes = 0; // Number of incoming bytes
  int serialInputInfo; // The input instruction

  // Readout and count
  int beamJoined = 0; //Track the number of times the beam was unbroken!
  int countUnbroken = 0; // Count how many times the beam was joined again after having been broken once (to initiate observation).
  int beamState = 1;
  int previousBeamState = 0; // Detect change in the beam state compared to prior state
  bool doCounting = 0; // Boolean to check whether events need to be counted

void serialEvent1(){
// Only try reading bytes when they are available 
serialInputInfo = Serial1COM.readByte(); // For some reason one needs to refer to SerialCOM1 here rather than Serial1.
////--------Checking---------/////
     Serial.print("serialInputInfo: ");
     Serial.println(serialInputInfo); //If connected via USB report the input info in the serial viewer
     Serial.print("\n");
     ////////////////////////////////////
      
     switch (serialInputInfo) { // Check the input information
            case SEND_MODULE_INFO:
            returnModuleInfo();
            break;
  
            case START_COUNTING:
            doCounting = 1;
            countUnbroken = 0; //This is important because stuff might happen before...
            break;

            case STOP_COUNTING:
            doCounting = 0;
            break;

            case REPORT_COUNT:
              if (countUnbroken == 0) { // Send either success or fail back to Bpod
                 Serial1.write(OBSERVER_FIXATION_SUCCESS);
              } else {
                  Serial1.write(OBSERVER_FIXATION_FAIL); 
              }

              ////----Checking-------/////
              Serial.print("Number of times beam joined: ");
              Serial.println(countUnbroken); // If connectd to USB report number of unbreakings
              Serial.print("\n");
              ////------------------////

              break;
              
              default:
              break;
      }
}

void loop() {
    // Check for changes in the beam state
    beamState = digitalRead(BeamBreakReadoutPin); //Get the current beam break state
    if (beamState != previousBeamState) {
      if (beamState == 0) {
        Serial1.write(BEAM_BROKEN);
        Serial.print("Beam broken");
        Serial.print("\n");
        /////////////////
      }   else if (beamState == 1) {
        Serial1.write(BEAM_JOINED);
        countUnbroken++; //Do the actual counting
        ////-----Checking--------/////
        Serial.print("Beam joined");
        Serial.print("\n");
        ////////////////
      }
      previousBeamState = beamState;
      
    }
}


//-------Define the module info return function----------------//
void returnModuleInfo() {
  Serial1COM.writeByte(65); // Acknowledge
  Serial1COM.writeUint32(FirmwareVersion); // 4-byte firmware version
  Serial1COM.writeByte(sizeof(moduleName) - 1); // Length of module name
  Serial1COM.writeCharArray(moduleName, sizeof(moduleName) - 1); // Module name
  Serial1COM.writeByte(0); // 1 if more info follows, 0 if not
}

///////////////////////////////////////////////////////////////////////////////////////////
