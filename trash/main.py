import socket
import os


local_files = os.listdir('.')
print(f'files:\n{local_files}')

server = socket.socket(socket.AF_INET,socket.SOCK_STREAM)

server.bind(('0.0.0.0',8080))

server.listen(1)

http_ok = "HTTP/1.1 200 OK "



while True:
    client,addr = server.accept()
    
    data = client.recv(1024)
    lines = data.decode().split('\n')
    print(lines[0])

    request = lines[0]

    print(f"request : {request}")
    path = request.split(" ")[1]



    response = ""
    response += "HTTP/1.1 200 OK\r\n"

    args = path.split("/")
    print(args)
    if args[1] == "echo" and len(args)==3:
        response += "Content-Type: text/plain\r\n"
        response += f"Content-Length: {len(args[2])}\r\n"
        response += "\r\n"
        response += f"{args[2]}\r\n"
    elif len(args)==2:
        file = args[1]
        data = b"0"

        for file_name in local_files:
            if file_name == file:
                print(f'file found {file_name}')
                with open(file_name, 'rb') as file_data:
                    data = file_data.read()

        print(f'file requested: {file}')
        if data == b"0":
            response = "HTTP/1.1 404  Not Found\r\n"
            response += "Content-Type: text/plain\r\n"
            response += f"Content-Length: {len('file not found\r\n')}\r\n"
            response += "\r\n"
            response += "file not found\r\n"
        else:
            response += f"Content-Length: {len(data)}\r\n"
            response += "\r\n"
            client.send(response.encode() + data)
            client.close()
            continue
    else:
        response += "\r\n"
    print(f"response: {response}")
    client.send(response.encode())

    client.close()
