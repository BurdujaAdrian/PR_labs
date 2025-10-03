import socket
import sys
import os

def get(addr:str,port:int,path:str)->tuple[bytes,bool]:
    client_sock = socket.socket(socket.AF_INET,socket.SOCK_STREAM)

    try:
        print(f"Connecting to {addr}{port}")
        client_sock.connect((addr,port))

        request = f"GET /{path} HTTP/1.1\r\n"+\
                  f"Host: {addr}\r\n\r\n"

        print(f"Sending request {request}")
        client_sock.sendall(request.encode())

        response = b""

        while True:
            print(f"Recieving packets:")
            packet = client_sock.recv(4096)
            if len(packet) == 0:
                break

            response += packet

        return response,True
    except Exception as e:
            return f"Exception: {e}".encode(),False

    finally:
        client_sock.close()

def get_parsed(addr:str,port:int,path:str)->tuple[bytes,int,bool]:
    response, ok = get(addr,port,path)
    if not ok:
        return response,0,False
    
    headers, body= response.split(b"\r\n\r\n",1)
    
    code = int(headers.split(b" ")[1])

    return body,code,True


args = sys.argv

if len(args) < 2:
    print("specify path and output folder")
    os._exit(1)
addr,path = args[1].split("/",1)
print(addr,path)
file_name = path.split("/")[-1]


if len(args) < 3:
    print("Specify output path")
    os._exit(1)

output = args[2]

data,code,ok = get_parsed(addr,8080,path)

if not ok:
    print("not ok",data)
    os._exit(1)

with open(file_name, 'wb') as file:
    file.write(data)


