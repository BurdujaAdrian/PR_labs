package main

import "base:builtin"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import str "core:strings"
import "core:time"

buff: [4096]byte

server_up := true

main :: proc() {

	// tcp
	server_endpoint := net.Endpoint{net.IP4_Any, 8080}

	server, err := net.listen_tcp(server_endpoint)
	defer net.close(server)

	for server_up {

		if err != nil {
			fmt.println("Failed to liten to tcp:", err)
			return
		}

		client, addr, err := net.accept_tcp(server)
		if err != nil {
			fmt.println("Accept error:", err)
			continue
		}

		handle_client(client)

	}
}

handle_client :: proc(client: net.TCP_Socket) {
	arena: mem.Arena

	buffer := make([]byte, 4096)
	mem.arena_init(&arena, buffer)
	context.allocator = mem.arena_allocator(&arena)


	fmt.println("\n=============\nBegin client session")
	tcp_buff := make([]byte, 1024)
	defer {
		fmt.println("End client session\n=============")
		net.close(client)
		delete(buffer)
	}

	for {

		read, read_err := net.recv_tcp(client, tcp_buff)
		fmt.println("bytes: ", read)
		if read_err != nil {
			fmt.println("Read error:", read_err)
			return
		}


		parts, _ := str.split_n(string(tcp_buff[:read]), " ", 3)
		request := parts[1]

		is_dir := request[len(request) - 1] == '/'
		response: []byte

		if is_dir {
			fmt.println("it's a dir")

			response = ls_cwd()

		} else {
			fmt.println("its a file")
			response = ok_response(transmute([]u8)(request))
		}


		_, err := net.send_tcp(client, response)

		if err != nil {
			fmt.println("Error while sending response:", err)
			return
		}

		if request[1:] == "exit" {
			fmt.println("Requested to exit")
			server_up = false
		}

		return
	}
}

ls_cwd :: proc() -> []byte {
	sb := str.builder_make()

	return sb.buf[:]
}

not_found_response :: #force_inline proc() -> []byte {
	return transmute([]byte)string("HTTP/1.1 404 Not Found\r\n\r\n")
}

server_err_response :: #force_inline proc(err: $T) -> []byte {
	sb := str.builder_make()
	fmt.sbprintf(&sb, "HTTP/1.1 505 Internal Server Error\r\n" + "%v\r\n", err)
	return sb.buf[:]
}
ok_response :: #force_inline proc(
	data: []byte,
	content: string = "text/plain",
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	response: []byte,
) {
	sb := str.builder_make()
	fmt.sbprintf(
		&sb,
		"HTTP/1.1 200 Ok\r\n" + "Content-Type: %s\r\n" + "Content-Length: %s\r\n\r\n",
		content,
		len(data),
	)
	n := str.write_bytes(&sb, data)
	return sb.buf[:]
}
