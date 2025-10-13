import socket
import os
from concurrent.futures import ThreadPoolExecutor, thread
import threading
import time
now = time.time

RATE_LIMIT = 50
DELAY = 3
race_start:float = 0

def INFO(msg):print(f"[INFO]:{msg}")
def DEBUG(msg): print(f"[DEBUG]:{msg}")


class DummyLock:
    def __init__(self) -> None: pass
    def read(self): return self.Reader_Lock(self)
    def write(self): return self.Writer_Lock(self)

    class Reader_Lock:
        def __init__(self,lock): pass 
        def __enter__(self): return self
        def __exit__(self, exc_type, exc_val, exc_tb): pass

    class Writer_Lock:
        def __init__(self,lock): pass
        def __enter__(self): return self
        def __exit__(self, exc_type, exc_val, exc_tb): pass

class RW_Lock:
    def __init__(self):
        self.lock_read = threading.Lock()
        self.lock_write = threading.Lock()
        self.lock_readers = threading.Lock()
        self.readers = 0 
        
    class Reader_Lock:
        def __init__(self,lock):  self.rwlock = lock
        def __enter__(self): return self
        def __exit__(self, exc_type, exc_val, exc_tb): self.rwlock.end_read()

    class Writer_Lock:
        def __init__(self,lock): self.rwlock = lock
        def __enter__(self): return self
        def __exit__(self, exc_type, exc_val, exc_tb): self.rwlock.end_write()

    def read(self):
        # guard against write starvation,writers take precedence
        # in order to write, one must first be able to aquire the read lock
        self.lock_read.acquire()
        self.lock_read.release() # release it imediatly after

        self.lock_readers.acquire()
        self.readers +=1
        if self.readers == 1: self.lock_write.acquire()
        self.lock_readers.release()

        return self.Reader_Lock(self)
        

    def end_read(self):
        assert self.readers > 0
        self.lock_readers.acquire()
        self.readers -=1
        if self.readers == 0: self.lock_write.release()
        self.lock_readers.release()

    def write(self):
        self.lock_read.acquire()
        self.lock_write.acquire()

        return self.Writer_Lock(self)

    def end_write(self):
        self.lock_write.release()
        self.lock_read.release()


# maps client ip to last timestamp and number of tries
client_map:dict[str,tuple[float,int]] = {}
copy_client_map:dict[str,tuple[float,int]] = {}
MAX_ENTRIES = 1000

def cleanup_file_map():
    for (ip,(timestamp,requests)) in copy_client_map.items():
        if timestamp > now() + 60: del copy_client_map[ip]

multithreaded = True
threadsafe = True

if threadsafe:
    files_lock = RW_Lock()
    caches_lock = RW_Lock()
else:
    files_lock = DummyLock()
    caches_lock = DummyLock()

file_map:dict[str,int] = {}
cache_map:dict[str,bytes] = {}


def not_found(): return "HTTP/1.1 404 Not Found\r\n\r\n"

def server_error(e:Exception)->str:
    excp = f"{e}"
    return "HTTP/1.1 500 Internal Server Error\r\n" + \
           "Content-Type: text/plain\r\n" + \
          f"Content-Length: {len(excp)}\r\n\r\n" + \
          f"{excp}"

def ok_html(data:str)->str:
    return "HTTP/1.1 200 OK\r\n" + \
           "Content-Type: text/html\r\n" + \
          f"Content-Length: {len(data)}\r\n\r\n" + \
          f"{data}"


def respond_dir(args: list[str]) -> str:
    print("")
    path = "./"
    for a in args: path += a + "/"

    with files_lock.write():
        if path in file_map: file_map[path] +=1
        else:file_map[path] = 1

    files = []
    try: files = os.listdir(path)
    except FileNotFoundError: return not_found()
    except Exception as e: return server_error(e)
    
    html_content  =  "<html><head><title>Lab1</title></head><body>"
    html_content += f"<h1>Directory Listing for {path}</h1><ul>"
    html_content += "<table border='1' >"
    html_content += "<tr><th>File/Directory</th><th>Hits</th></tr>"
    html_content += "<hr>"
    for file in files:
        if os.path.isdir(os.path.join(path, file)): 
            file_path = f"{path}{file}/"

            entry:int = 0
            with files_lock.write():
                if file_path not in file_map: file_map[file_path] = 0
                
                entry = file_map[file_path]

            html_content += f'<tr><td><a href="{file}/">{file}/</a> </td><td>{entry}</a></td></tr>'
        else:
            file_path = f"{path}{file}"

            entry:int = 0
            with files_lock.write():
                if file_path not in file_map: file_map[file_path] = 0
                
                entry = file_map[file_path]
           
            html_content += f'<tr><td><a href="{file}">{file}</a> </td><td> {entry}</a></td></tr>'
    
    html_content += "</table>"
    html_content += "<hr>"
    html_content += "</body></html>"
    
    return ok_html(html_content)



def respond_file(args:list[str])->tuple[str,bytes]:
    DEBUG(f"\tStart responding file:{now().__ceil__() %100}")
    path = "./"+args[0]
    for a in args[1:]: path += "/"+a

    content_type = ""
    if path.split(".")[-1] == "html": content_type = "text/html"
    elif path.split(".")[-1] == "pdf": content_type = "application/pdf"
    elif path.split(".")[-1] == "png": content_type = "image/png"
    else: return not_found(),b""

    data:bytes

    should_open_file = True
    with caches_lock.read(): should_open_file = (path not in cache_map) or not (cache_map[path])
    
    if should_open_file:
        try:
            with open(path, 'rb') as FileData:  data = FileData.read()
        except Exception as e: return server_error(e), b""

        with caches_lock.write(): cache_map[path] = data
    else:
        data = b""
        with caches_lock.read(): data = cache_map[path]


    DEBUG(f"\tjust before sleep:{now().__ceil__()%100}")
    with files_lock.write():
        if path not in file_map: 
            #force race condition
            time.sleep(now() - race_start )
            file_map[path] = 1
        else: file_map[path] +=1

    response = "HTTP/1.1 200 Ok \r\n"+\
              f"Content-Type: {content_type}\r\n"+\
              f"Content-Length: {len(data)}\r\n\r\n"

    DEBUG(f"\tFinished formulating request:{now().__ceil__()%100}")
    return response,data

def handle_client(client:socket.socket):
    DEBUG(f"Request recieved and started{now().__ceil__()%100}")
    time.sleep(DELAY)
    try:
        data = client.recv(1024)
        lines = data.decode().split('\r\n')
        request = lines[0]

        #if some malformed request occured
        if request == "":  client.close();return

        path = request.split(" ")[1]
        path = path.replace("%20"," ")

        is_dir = path[-1] == "/"
        args = path.split("/")
        args = [arg for arg in args if arg != ""]

        if is_dir:
            response = respond_dir(args)
            client.send(response.encode())
        else:
            response,data = respond_file(args)
            client.send(response.encode() + data)
            if args[0] == "exit": os._exit(0)
    except Exception as e:
        client.send(server_error(e).encode())
    finally:
        DEBUG(f"Request finished and sent{now().__ceil__()%100}")
        client.close()




def main():
    global client_map, copy_client_map,race_start
    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as server: 
        server.bind(('0.0.0.0',8080))
        server.listen(8)

        if not multithreaded:
            while True:
                client,addr = server.accept()
                handle_client(client)
        else:
            with ThreadPoolExecutor(max_workers=8) as pool:
                while True:
                    if len(client_map) > MAX_ENTRIES:
                        temp = client_map
                        client_map =copy_client_map
                        copy_client_map = temp
                        pool.submit(cleanup_file_map)


                    client,addr = server.accept()
                    client_ip =addr[0]

                    if client_ip not in client_map: client_map[client_ip] = (now(),1)
                    else:
                        (timestamp, requests) = client_map[client_ip]
                        if requests <= RATE_LIMIT: client_map[client_ip] = (now(), requests +1)
                        else:# if a second or more passed reset
                            if now() - timestamp >= 1: client_map[client_ip] = (now(),1)
                            else:
                                INFO("Hit rate limit lmao")
                                client.close()
                                continue # skip the client

                    race_start = now()
                    pool.submit(handle_client,client)


if __name__ == "__main__": main()
