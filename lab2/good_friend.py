from client import get
from threading import Thread
from time import sleep

def work_function(self,path):
    data,ok = get("192.168.100.250",8080,path)
    if ok:
        print("Data succesfully recieved")
    else:
        print("Error occured:",data.decode())
    pass


jobs = []

for _ in range(0,20):
    work = Thread(target=work_function,args=("./"))
    sleep(1)
    work.start()
    jobs.append(work)

for work in jobs:
    work.join()
