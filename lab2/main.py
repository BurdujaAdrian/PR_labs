import socket
import os
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor


@dataclass
class FileRecord:
    data:bytes
    counter:int


client_map:dict[tuple[str, int],int] = {}
file_map:dict[str,FileRecord] = {}

def print_files(map_of_files:dict[str,FileRecord]):
    for keys,value in map_of_files.keys():
        print(f"keys:{keys}, value:{value}")

def not_found():
    return "HTTP/1.1 404 Not Found\r\n\r\n"

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


    path = "./"
    for a in args:
        path += a + "/"

    if path in file_map:
        file_map[path].counter +=1
    else:
        file_map[path] = FileRecord(b"",1)

    files = []
    try:
        files = os.listdir(path)
    except FileNotFoundError:
        return not_found()
    except Exception as e:
        return server_error(e)
    
    html_content  =  "<html><head><title>Lab1</title></head><body>"
    html_content += f"<h1>Directory Listing for {path}</h1><ul>"
    html_content += "<table border='1' >"
    html_content += "<tr><th>File/Directory</th><th>Hits</th></tr>"
    html_content += "<hr>"
    for file in files:

        if os.path.isdir(os.path.join(path, file)):
            file_path = f"{path}{file}/"
            if file_path not in file_map:
                file_map[file_path] = FileRecord(b"",0)
            
            entry = file_map[file_path]
            html_content += f'<tr><td><a href="{file}/">{file}/</a> </td><td>{entry.counter}</a></td></tr>'
        else:
            
            file_path = f"{path}{file}"
            if file_path not in file_map:
                file_map[file_path] = FileRecord(b"",0)
            
            entry = file_map[file_path]
            html_content += f'<tr><td><a href="{file}">{file}</a> </td><td> {entry.counter}</a></td></tr>'
    
    html_content += "</table>"
    html_content += "<hr>"
    html_content += "</body></html>"
    
    return ok_html(html_content)



def respond_file(args:list[str])->tuple[str,bytes]:

    path = "./"+args[0]
    for a in args[1:]:
        path += "/"+a


    content_type = ""
    if path.split(".")[-1] == "html":
        content_type = "text/html"
    elif path.split(".")[-1] == "pdf":
        content_type = "application/pdf"
    elif path.split(".")[-1] == "png":
        content_type = "image/png"
    else:
        return not_found(),b""

    data:bytes
    if (path not in file_map) or not (file_map[path].data):
        try:
            with open(path, 'rb') as FileData:
                print("reading file:",path)
                data = FileData.read()
        except Exception as e:
            return server_error(e), b""
    else:
        data = file_map[path].data

    if path not in file_map:
        file_map[path] = FileRecord(data,1)
    else:
        file_map[path].counter +=1

    response = "HTTP/1.1 200 Ok \r\n"+\
              f"Content-Type: {content_type}\r\n"+\
              f"Content-Length: {len(data)}\r\n\r\n"

    return response,data



def handle_client(client:socket.socket):
    data = client.recv(1024)
    lines = data.decode().split('\r\n')
    request = lines[0]

    if request == "": #if some malformed request occured
        client.close()
        return

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
        if args[0] == "exit":
            os._exit(0)

    client.close()

def main():
    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as server: 
        server.bind(('0.0.0.0',8080))
        server.listen(8)

        if True:
            while True:
                client,addr = server.accept()
                handle_client(client)
        else:
            with ThreadPoolExecutor(max_workers=8) as pool:
                while True:
                    client,addr = server.accept()
                    _ = addr[1]
                    pool.submit(handle_client,client)

if __name__ == "__main__":
    main()
