import os
import serial
import serial.tools.list_ports
from time import strftime, gmtime, sleep
import socket #To establish udp connection to the behavior computer
 
#%%-----Find available teensy and establish connection---------
ports = serial.tools.list_ports.comports(include_links=False)
for port in ports :
    portsList = [port.device]
  
if (len(portsList) == 1):
    teensyCOM = serial.Serial(portsList[0], 9600) #Establish connection at matching rate!
    print("Connected to teensy on " + portsList[0])
elif (len(portsList) > 1):
    teensyPortID = input("Multiple COM ports are connected. Please specify the recording teensy: ")
    teensyCOM = serial.Serial(teensyPortID, 9600) #Establish connection at matching rate!
    print("Connected to teensy on " + teensyPortID)
else:
    print("No COM port available. Please check teensy connection")
    
    
#%%----Establish connection with the behavior computer and fetch info about
#      the animal, session name and miniscope.

server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
#Start a UDP socket. The SOCK_DGRAM specifies the UDP connection protocol

server_socket.bind(('', 6003))
#Make this socket listen to port 6003. Since this is the server that will
#be contacted by a client one doesn't need to specify the IP address here.

message = []
client_address = []
while len(client_address) == 0: #This loop listens until the client sends a message over
    #clientsocket, cl_address = server_socket.accept()
    message, client_address = server_socket.recvfrom(1024)  #Assign a maximum of 1024 bytes that can be read at once

print("Received animal, session and minisope information. Sending acknowledgement back.")

#server_socket.sendto(str.encode("Fake news!"), client_address) #Test for non-matching message
server_socket.sendto(message, client_address) #Acknowledge the message 


#%%-----Create a file and write a header---------
rootDirectory = "C:/Users/Anne/Documents/Bpod Local/Data"

animalID = input("Please specify the animal name: ")
fileTime = strftime("%Y%m%d_%H%M%S", gmtime())
#Find the respective directory
logFileName = (animalID + "_" + fileTime + "_miniscope.mscopelog")
logFileDirectory = os.path.join(rootDirectory, animalID, fileTime, "miniscope")

#Check if directory exists and create otherwise
if not os.path.exists(logFileDirectory):
    os.makedirs(logFileDirectory)
    
logFilePath = os.path.join(logFileDirectory, logFileName)
output_file = open(logFilePath, "w+")

#%%------Write file header info---------


#%%-----INTERMEDIATE: Let user start and stop synchronization-------------
#input("Press enter to start the acquisition. Press any key and enter to stop")

#%%----Acquire messages from teensy and write to file
teensyCOM.write(str.encode('1')) #Send a byte (49) to reset the counting of frames and start interrupts

#and trials.
sporadicReport = 0; #Sporadically report that syncing is still on
counter = 0;
#goFlag = True
try:
    while True:
        signal = teensyCOM.read()
        entry = signal.decode("utf-8")
        output_file.write(entry);
        print(entry)
        teensyCOM.reset_output_buffer()
        #teensyCOM.flushOutput()
        #teensyCOM.reset_input_buffer() #Make sure to clear the buffer for new data
        #counter = counter+1
        #if counter == 10000:
            #    sporadicReport = sporadicReport
            #    print("Received", sporadicReport*counter, "individual bytes")
            #    counter = 0
except KeyboardInterrupt:
    #---Stop acquisition and close the file-------------------------
    #teensyCOM.write(str.encode('0')) #Send a byte (48) to stop the interrupts
    output_file.close()
    teensyCOM.close()
    print("Synchronization ended")

