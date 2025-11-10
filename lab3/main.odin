#+feature global-context
package main

import "core:fmt"
import "core:hash/xxhash"
import "core:log"
import "core:mem"
import "core:net"
import "core:os"
import "core:os/os2"
import "core:slice"
import "core:strconv"
import str "core:strings"
import "core:sync"
import http "odin-http"


//@helper generic
unwrap :: #force_inline proc(something: $T, ok: $D, loc := #caller_location) -> T {
	assert_contextless(ok, loc = loc)
	return something
}

atoi :: #force_inline proc(num: string, loc := #caller_location) -> int {
	return unwrap(strconv.parse_int(num, 10), loc)
}

hash :: #force_inline proc(text: string) -> (res: u64) {
	res = xxhash.XXH3_64_default(transmute([]u8)text)
	assert(res != NO_STRING)
	return
}


main :: proc() {
	args := os2.args
	file: string

	switch len(args) {
	case 1:
		fmt.panicf("In order to start the server, please provide a file as argument")
	case:
		file = args[1]
	}

	_board_w, _board_h, _hash_map, _board = parse_board(file)

	/*
	*	Lock hierarchy:
	*	player > board > watch
	*/


	e := Effect {
		_board,
		_board_w,
		_board_h,
		_board_lock,
		_hash_map,
		_update_watch,
		_update_lock,
		_was_updated,
	}

	router: http.Router
	http.router_init(&router)


	http.route_get(&router, "/look/(.+)", {
		user_data = &e,
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
			e := cast(^Effect)h.user_data
			req_arena: mem.Arena
			req_buff: [4096]u8
			mem.arena_init(&req_arena, req_buff[:])
			context.allocator = mem.arena_allocator(&req_arena)


			player_name := req.url_params[0]
			fmt.assertf(
				str.count(player_name, " ") == 0,
				"Player name should not have any empty spaces",
			)
			player_id := hash(player_name)

			boardstate: string
			boardstate = look(player_id, e)

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)

		},
	})
	http.route_get(&router, "/watch/(.+)", {
		user_data = &e,
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
			e := cast(^Effect)h.user_data
			req_arena: mem.Arena
			req_buff: [4096]u8
			mem.arena_init(&req_arena, req_buff[:])
			context.allocator = mem.arena_allocator(&req_arena)


			player_name := req.url_params[0]
			player_id := hash(player_name)

			boardstate := watch(player_id, e)

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)
		},
	})

	http.route_get(&router, "/replace/(.+)/(.+)/(.+)", {
		user_data = &e,
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {

			e := cast(^Effect)h.user_data

			req_arena: mem.Arena
			req_buff: [4096]u8
			mem.arena_init(&req_arena, req_buff[:])
			context.allocator = mem.arena_allocator(&req_arena)

			player_name := req.url_params[0]
			player_id := hash(player_name)
			state: http.Status = .OK

			from, _ := net.percent_decode(req.url_params[1])
			to, _ := net.percent_decode(req.url_params[2])

			boardstate, err := replace(to, from, player_id, e)
			if err == .Conflict {
				state = http.Status.Conflict
			}

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate, status = state)
		},
	})

	http.route_get(&router, "/flip/(.+)/(.+)", {
		user_data = &e,
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {

			e := cast(^Effect)h.user_data

			req_arena: mem.Arena
			req_buff: [4096]u8
			mem.arena_init(&req_arena, req_buff[:])
			context.allocator = mem.arena_allocator(&req_arena)


			player_name := req.url_params[0]
			player_id := hash(player_name)

			loc_str, _ := str.split(req.url_params[1], ",")
			tile_pos: int = atoi(loc_str[0]) * e.board_w + atoi(loc_str[1])

			status: http.Status = .OK

			boardstate, err := flip(player_id, tile_pos, e)

			if err != .Ok {
				status = .Conflict
			}

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate, status)
		},
	})

	{ 	// `deploy` server
		when ODIN_DEBUG {context.logger = log.create_console_logger(
				.Debug,
			)} else {context.logger = log.create_console_logger(.Info)}

		s: http.Server
		http.server_shutdown_on_interrupt(&s)
		handler := http.router_handler(&router)
		if err := http.listen_and_serve(
			&s,
			handler,
			http.Default_Endpoint,
			http.Server_Opts {
				thread_count = 6,
				auto_expect_continue = true,
				redirect_head_to_get = true,
				limit_request_line = 8000,
				limit_headers = 8000,
			},
		); err != nil {
			fmt.eprintln("Listen and server Error:", err)
		}
	}

}
