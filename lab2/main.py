import socket
import os

from concurrent.futures import ThreadPoolExecutor


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

    files = []
    try:
        files = os.listdir(path)
    except FileNotFoundError:
        return not_found()
    except Exception as e:
        return server_error(e)
    
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

    try:
        with open(path, 'rb') as file_data:
            data = file_data.read()
    except Exception as e:
        return server_error(e), b""


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

        with ThreadPoolExecutor(max_workers=8) as pool:
            while True:
                client,_ = server.accept()
                pool.submit(handle_client,client)

if __name__ == "__main__":
    main()
