import os
import serial
import serial.tools.list_ports
from time import strftime, gmtime, time
import socket #To establish udp connection to the behavior computer
import json
from labdatatools import rclone_upload_data

#%%-----Make sure to provide a directory containing a Data folder and a
#       Protocols folder where chipmunk lives or change here

root_directory = "C:/Users/Anne/Documents/Bpod Local"
miniscope_software_directory = "C:/Users/Anne/Documents"
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
    print("No COM port available. Please check teensy connection.")
    

#%%----Establish connection with the behavior computer and fetch info about
#      the animal, session name and miniscope.
port_number = 9998 #Degine this here for now

server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
 #Start a UDP socket. The SOCK_DGRAM specifies the UDP connection protocol
    
server_socket.bind(('', port_number))
    #Make this socket listen to port 6003. Since this is the server that will
    #be contacted by a client one doesn't need to specify the IP address here.
    
print(f"Start listening to port {port_number} for chipmunk information...")
message = []
client_address = []
while len(client_address) == 0: #This loop listens until the client sends a message over
      #clientsocket, cl_address = server_socket.accept()
      message, client_address = server_socket.recvfrom(1024)  #Assign a maximum of 1024 bytes that can be read at once
    
print("Received animal, session and minisope information. Sending acknowledgement back.")

#server_socket.sendto(str.encode("Fake news!"), client_address) #Test for non-matching message
server_socket.sendto(message, client_address) #Acknowledge the message 

session_info = str.split(message.decode(), sep=',')
animal_id = session_info[0]
session_date_time = session_info[1]
miniscope_id = session_info[2]

#%%---Generate the config file to be used with the miniscope

#Load a standard config file from  the MiniscopeTools folder in chipmunk
standard_config = root_directory + "/Protocols/chipmunk/MiniscopeTools/standardMiniscopeConfig.json"
f = open(standard_config, 'r')
miniscope_config = json.load(f)
f.close()

#Assign the correct directory, matching the animal and the session
data_directory = os.path.join(miniscope_config['dataDirectory'], animal_id, session_date_time, "miniscope") #Assign and create the directory
os.makedirs(data_directory)

config_directory = os.path.join(miniscope_config['dataDirectory'], animal_id, session_date_time)
#Since the miniscope software will create subdirectories of the one passed as input
#we will pass the directory one level above as input to the DAQ software
miniscope_config['dataDirectory'] = config_directory
miniscope_config['devices']['miniscopes']['miniscope']['deviceName'] = miniscope_id

#Create a json file in the session's miniscope folder
miniscope_config_out = data_directory + "/" + animal_id + "_miniscopeConfig.json"
with open(miniscope_config_out,'w') as f : 
    json.dump(miniscope_config, f)


#%%-----Create the mscopelog file file and write a header---------
# rootDirectory = "C:/Users/Anne/Documents/Bpod Local/Data"

# animalID = input("Please specify the animal name: ")
# fileTime = strftime("%Y%m%d_%H%M%S", gmtime())
# #Find the respective directory

logFileName = (animal_id + "_" + session_date_time + "_miniscope.mscopelog")
#logFileDirectory = os.path.join(rootDirectory, animalID, fileTime, "miniscope")

#Check if directory exists and create otherwise
# if not os.path.exists(logFileDirectory):
#     os.makedirs(logFileDirectory)
    
logFilePath = os.path.join(data_directory, logFileName)
output_file = open(logFilePath, "w+")

print("Prepared a config file for miniscope acquisition. Please start miniscope recording with the following file:")
print(f"{miniscope_config_out}")

#%%------Write file header info---------


#%%-----INTERMEDIATE: Let user start and stop synchronization-------------
#input("Press enter to start the acquisition. Press any key and enter to stop")

#%%----Acquire messages from teensy and write to file
teensyCOM.write(str.encode('1')) #Send a byte (49) to reset the counting of frames and start interruptsand trials.

acquisition_start= time(); #Keep track of the start of the acquisition
last_report = 0; #Update time of the last reporting
current_time = 0; #Store time 

try:
    while True:
        signal = teensyCOM.read()
        entry = signal.decode("utf-8")
        output_file.write(entry);
        #print(entry)
        teensyCOM.reset_output_buffer()
        
        current_time = time()
        if (current_time - last_report) > 120: #Update every 2 min
            print(f"Synchronization ran for {round(current_time - acquisition_start)} s.")
            last_report = current_time
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
    del server_socket
    print("Synchronization ended")
#%%-----Use labdatatools to upload the data to the google drive
    print("Starting to upload the miniscope data...")
    rclone_upload_data(subject = animal_id, session = session_date_time, datatype = 'miniscope')