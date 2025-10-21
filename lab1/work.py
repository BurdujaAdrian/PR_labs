from client import get
from threading import Lock,Thread

def work_function(self,path):
    data,ok = get("localhost",8080,path)
    if ok:
        print("Data succesfully recieved:",data.decode())
    else:
        print("Error occured:",data.decode())
    pass


jobs = []

for _ in range(0,10):
    work = Thread(target=work_function,args=("./"))
    work.start()
    jobs.append(work)

for work in jobs:
    work.join()
