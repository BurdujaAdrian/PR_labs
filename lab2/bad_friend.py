from client import get
from threading import Thread

def work_function(self,path):
    data,ok = get("192.168.100.251",8080,path)
    if ok:
        print("Data succesfully recieved")
    else:
        print("Error occured:",data.decode())
    pass


jobs = []

for _ in range(0,100):
    work = Thread(target=work_function,args=("./"))
    work.start()
    jobs.append(work)

for work in jobs:
    work.join()
