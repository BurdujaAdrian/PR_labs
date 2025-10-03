# Lab1

## Elaborated by: Burduja Adrian faf231

### Theory
In order to create a http server(without using a dedicated library) it's requred to use the tools the operating
sysem provides: tcp api.

This api varies by operating system but often times, it is abstracted over core libraries.

Python has such library: socket. It deals with system sockets over which network communication occurs.

Sockets are a very simply concept, they are simply an ip address and port pair. 
The system has a limited number of ports, some of which are usually used by particular protocols. In particular, http is usually done over port 80, but sometimes people use 8080 or 8090 as well.

According to Wikipedia:

HTTP (Hypertext Transfer Protocol) is an application layer protocol in the Internet 
protocol suite model for distributed, collaborative, hypermedia information systems. 
HTTP is the foundation of data communication for the World Wide Web, where hypertext 
documents include hyperlinks to other resources that the user can easily access, for
example by a mouse click or by tapping the screen in a web browser.

HTTP functions as a request–response protocol in the client–server model. A web browser
, for example, may be the client whereas a process, named web server, running on a 
\computer hosting one or more websites may be the server. The client submits an HTTP 
request message to the server. The server, which provides resources such as HTML files
and other content or performs other functions on behalf of the client, returns a 
response message to the client. The response contains completion status information 
about the request and may also contain requested content in its message body.
### Implementation:server

To use a socket, the python code must define it's values and bind it:
```main.py
server = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
server.bind(('0.0.0.0',8080))
server.listen(1)
```

In the sockets library in particular, it's possible to define the maximum number of 
incomming connections. It was set to 1 as the server is single threaded anyways, it 
can only process 1 request at a time.

For the server to continuously server files, an infinite loop is requred:
```main.py

while True:
    client,addr = server.accept()
    # rest of the code
    client.close()

```

When the server recieves a connection, it needs to record the socket of the client and 
the return address.

```main.py
    data = client.recv(1024)
    lines = data.decode().split('\n')
    request = lines[0]
```


The data from the client is recovered via the recv method. The data is in the form of 
a http response, which has a specific structure. The "request" is the first line, so
it can be sparated via ```lines[0]```.

```main.py
    path = request.split(" ")[1]
```

Next, the "path" is the query the client has sent to the server. Since this server is 
configured to expect GET requests, it assumes any request is a get request. This could
be an issue in a real project however this is acceptable if no requiremnt specifically
asks for it. So, ```request.split(" ")[1]``` is sufficient to get the path.

```main.py
    if is_dir:
        response = respond_dir(args)
        client.send(response.encode())
    else:
        response,data = respond_file(args)
        client.send(response.encode() + data)
        if args[0] == "exit":
            os._exit(0)
```

This is the most vital part of the program, it dicides how to process the request.
```respond_dir``` returns a generated html text to show the files in the directory
requested.

```respond_file``` will return the text file requested, if it is a html file, else
it return a 404 response:
```main.py
def not_found():
    return "HTTP/1.1 404 Not Found\r\n\r\n"
```

Since both ```respond_*``` functions usually return a html file, they both have a 
similar mechanism for formting the response:
```main.py
    response = "HTTP/1.1 200 Ok \r\n"+\
               "Content-Type: text/html\r\n"+\
              f"Content-Length: {len(data)}\r\n\r\n"

    return response,data
```

Here we first add the response type with the first line (200 Ok in this case).
Then we specify the content type and length.

When it returns, the response together with the data is sent back to the client.


### Implementation:client

For the client, a simple library was the condition. In order to access the server,
only get requests are requred, therefore only the functions ```get``` and 
```get_parsed``` were implemented:

```client.py
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
```

Both functions take the same input: address of the server, the port it's serving on 
and the path or the file requested. ```get``` will send the get request, 
```get_parsed``` calls it but also parses the response to return only the body and the
request code.


### Conclusion
This laboratory successfully demonstrated the creation of a functional HTTP server from the ground up. We built a simple but effective web server that serves HTML files and provides directory listings using raw socket programming in Python. The project provided hands-on experience with HTTP protocol implementation, request parsing, and proper response formatting.

Through this exercise, we gained practical understanding of how web servers fundamentally operate - from handling TCP connections to generating valid HTTP responses with appropriate status codes and content types. The implementation also included Docker containerization for consistent deployment and a basic client library for testing server functionality.

While encountering real-world challenges like network configuration and concurrent connection handling, we developed a solid foundation in web server architecture. This project successfully bridges theoretical HTTP knowledge with practical implementation, providing essential insights into the underlying mechanics of web communication that power modern internet applications.




