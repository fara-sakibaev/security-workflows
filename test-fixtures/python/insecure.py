import subprocess

command = input("Synthetic command: ")
subprocess.Popen(command, shell=True)
