
import serial
import time

c = serial.Serial('COM3', 9600)

write_to_file_path = "C:/Users/Lukas Oesch/Documents/ChurchlandLab/Behavioral_cage_desing/testRunArduinoDaq/test.txt";
output_file = open(write_to_file_path, "w+");

while True:
    signal = c.read()
    #print(signal)
    entry = signal.decode("utf-8")
    output_file.write(entry);
    print(entry)
    print("running")
    c.flushOutput()
    time.sleep(0.2)
c.close()
output_file.close()



