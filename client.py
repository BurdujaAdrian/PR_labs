import os
import socket

def get(addr:str,port:int,path:str)->tuple[str,bool]:
    client_sock = socket.socket(socket.AF_INET,socket.SOCK_STREAM)

    try:
        client_sock.connect((addr,port))

        request = f"GET {path} HTTP/1.1\r\n"+\
                  f"Host: {addr}\r\n\r\n"

        client_sock.sendall(request.encode())

        response = b""

        while True:
            packet = client_sock.recv(4096)
            if len(packet) == 0:
                break

            response += packet

        return response.decode(),True
    except Exception as e:
            return f"Exception: {e}",False

    finally:
        client_sock.close()

def get_parsed(addr:str,port:int,path:str)->tuple[str,int,bool]:
    response, ok = get(addr,port,path)
    if not ok:
        return response,0,False
    
    headers, body= response.split("\r\n\r\n",1)
    
    code = int(headers.split(" ")[1])

    return body,code,True

print("testing")

print(get_parsed("localhost",8080,input()))


