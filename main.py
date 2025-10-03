import socket
import os


local_files = os.listdir('.')
print(f'files:\n{local_files}')

server = socket.socket(socket.AF_INET,socket.SOCK_STREAM)

server.bind(('0.0.0.0',8080))

server.listen(1)

def not_found():
    return "HTTP/1.1 404 Not Found\r\n\r\n"

def respond_dir(args: list[str]) -> str:
    path = "./"
    for a in args:
        path += a + "/"

    files = []
    try:
        files = os.listdir(path)
    except FileNotFoundError:
        return not_found()
    except Exception as e:
        excp = f"{e}"
        response = "HTTP/1.1 500 Internal Server Error\r\n" + \
                   "Content-Type: text/plain\r\n" + \
                  f"Content-Length: {len(excp)}\r\n" + \
                   "\r\n" + \
                  f"{excp}"
        return response
    
    html_content  =  "<html><head><title>Lab1</title></head><body>"
    html_content += f"<h1>Directory Listing for {path}</h1><ul>"
    
    html_content += "<hr>"
    for file in files:
        if os.path.isdir(os.path.join(path, file)):
            html_content += f'<li><a href="{file}/">{file}/</a></li>'
        else:
            html_content += f'<li><a href="{file}">{file}</a></li>'
    
    html_content += "<hr>"
    html_content += "</ul></body></html>"
    
    response = "HTTP/1.1 200 OK\r\n" + \
               "Content-Type: text/html\r\n" + \
              f"Content-Length: {len(html_content)}\r\n" + \
               "\r\n" + \
              f"{html_content}"

    return response


def respond_file(args:list[str])->tuple[str,bytes]:

    path = "./"+args[0]
    for a in args[1:]:
        path += "/"+a

    if path.split(".")[-1] != "html":
        return not_found(),b""
    try:
        with open(path, 'rb') as file_data:
            data = file_data.read()
    except Exception as e:
        excp = f"{e}|{e.__class__}"
        response = "HTTP/1.1 500 Internal Server Error\r\n" + \
                   "Content-Type: text/plain\r\n" + \
                  f"Content-Length: {len(excp)}\r\n" + \
                   "\r\n" + \
                  f"{excp}"
        return response, b""


    response = "HTTP/1.1 200 Ok \r\n"+\
               "Content-Type: text/html\r\n"+\
              f"Content-Length: {len(data)}\r\n\r\n"

    return response,data




while True:
    client,addr = server.accept()
    
    data = client.recv(1024)
    lines = data.decode().split('\n')
    request = lines[0]

    print(f"request : {request}")
    if request == "": #if some malformed request occured
        client.close()
        continue

    path = request.split(" ")[1]

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
    continue
