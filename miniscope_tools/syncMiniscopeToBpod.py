import os
import serial
import serial.tools.list_ports
from time import time
import socket #To establish udp connection to the behavior computer
import json
from labdatatools import rclone_upload_data

#%%-----Find available teensy and establish connection---------

ports = serial.tools.list_ports.comports(include_links=False)
portsList = [port.device for port in ports]
  
if (len(portsList) == 1):
    teensyCOM = serial.Serial(portsList[0], 9600) #Establish connection at matching rate!
    print("Connected to teensy on " + portsList[0])
elif (len(portsList) > 1):
    teensyPortID = input("Multiple COM ports are connected. Please specify the recording teensy: ")
    teensyCOM = serial.Serial(teensyPortID, 9600) #Establish connection at matching rate!
    print("Connected to teensy on " + teensyPortID)
else:
    raise SystemExit("No COM port available. Please check teensy connection.")


#%%----Establish connection with the behavior computer and fetch info about
#      the animal, session name and miniscope.
port_number = 9998

server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
server_socket.bind(('', port_number))

print(f"Start listening to port {port_number} for chipmunk information...")
message = []
client_address = []
while len(client_address) == 0:
      message, client_address = server_socket.recvfrom(1024)

print("Received animal, session and miniscope information. Sending acknowledgement back.")
server_socket.sendto(message, client_address) 

session_info = str.split(message.decode(), sep=',')
animal_id = session_info[0]
session_date_time = session_info[1]
miniscope_id = session_info[2]

#%%---Generate the config file to be used with the miniscope

standard_config = os.path.join(os.path.dirname(os.path.abspath(__file__)), "standardMiniscopeConfig.json")
f = open(standard_config, 'r')
miniscope_config = json.load(f)
f.close()

#Assign the correct directory, matching the animal and the session
data_directory = os.path.join(miniscope_config['dataDirectory'], animal_id, session_date_time, "miniscope") #Assign and create the directory
os.makedirs(data_directory, exist_ok=True)

config_directory = os.path.join(miniscope_config['dataDirectory'], animal_id, session_date_time)
#Since the miniscope software will create subdirectories of the one passed as input
#we will pass the directory one level above as input to the DAQ software
miniscope_config['dataDirectory'] = config_directory
miniscope_config['devices']['miniscopes']['miniscope']['deviceName'] = miniscope_id

#Create a json file in the session's miniscope folder
miniscope_config_out = data_directory + "/" + animal_id + "_miniscopeConfig.json"
with open(miniscope_config_out,'w') as f : 
    json.dump(miniscope_config, f)


#%%-----Create the mscopelog file and write a header---------
logFileName = (animal_id + "_" + session_date_time + "_miniscope.mscopelog")
logFilePath = os.path.join(data_directory, logFileName)
output_file = open(logFilePath, "a") # a restart for the same session appends; the frame count restarts at 0

print("Prepared a config file for miniscope acquisition. Please start miniscope recording with the following file:")
print(f"{miniscope_config_out}")

teensyCOM.write(str.encode('1')) # byte 49 resets the frame count and starts interrupts

acquisition_start= time(); #Keep track of the start of the acquisition
last_report = 0; #Update time of the last reporting
current_time = 0; #Store time 

try:
    while True:
        signal = teensyCOM.read()
        entry = signal.decode("utf-8")
        output_file.write(entry)
        teensyCOM.reset_output_buffer()

        current_time = time()
        if (current_time - last_report) > 120:
            print(f"Synchronization ran for {round(current_time - acquisition_start)} s.")
            last_report = current_time
except KeyboardInterrupt:
    pass
finally:
    output_file.close()
    teensyCOM.write(str.encode('0')) # byte 48 stops the interrupts
    teensyCOM.close()
    server_socket.close()
    print("Synchronization ended")

print("Starting to upload the miniscope data...")
rclone_upload_data(subject = animal_id, session = session_date_time, datatype = 'miniscope')