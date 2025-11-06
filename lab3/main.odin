#+feature global-context
package main

import "base:builtin"
import "base:runtime"
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
import "core:thread"
import "core:time"
import http "odin-http"

write_str :: str.write_string
write_int :: str.write_int
write_char :: str.write_rune

guard :: sync.mutex_guard

map_f :: slice.mapper
find :: slice.linear_search

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

pop_front :: #force_inline proc(list: ^[MAX_PLAYERS]u64) -> (front: u64) {
	front = list[0]
	#unroll for i in 0 ..< MAX_PLAYERS - 1 {
		list[i] = list[i + 1]
	}
	return
}

place_back :: #force_inline proc(list: ^[MAX_PLAYERS]u64, p_id: u64) {
	p_id := p_id
	#unroll for i in 0 ..< MAX_PLAYERS - 1 {
		if list[i] == 0 {
			list[i] = p_id
			p_id = 0
		}
	}
	// has inserted succesfully
	assert(p_id == 0)
}

//@server helpers
internal_error :: proc(res: ^http.Response, msg: string, err: $E) {
	log.error(msg, err)
	http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
	http.body_set_str(res, fmt.aprint(msg, err))
	http.respond_with_status(res, .Internal_Server_Error)
}

//@game helpers
find_player_pos :: proc(player_id: u64, e: ^Effect) -> (res: [2]int) {
	for id, i in e.board.owner[:e.board_size] {
		if player_id == id {
			switch {
			case res[0] == 0:
				res[0] = i + 1
			case res[1] == 0:
				res[1] = i + 1
			case:
				assert(res[0] != 0 && res[1] != 0)
				fmt.assertf(false, "Any player should not have more than 2 cards owned at a time")
			}
		}
	}
	return
}


evacuate_tile :: proc(pos: int, e: ^Effect) {

	if pos == -1 do return

	e.board[pos].owner = pop_front(&e.board[pos].wait_list)
	sync.cond_broadcast(&e.board[pos].watch)
}

gen_board :: proc(owner: u64, e: ^Effect, loc := #caller_location) -> string {
	fmt.assertf(
		owner != NO_STRING,
		"the owner when calling gen board should not be \"\"",
		loc = loc,
	)
	builder: str.Builder

	// unlikely to read the board in an invalid state. Also the board is a stabel
	// and static piece of memory
	if true  /* guard(&board_lock)*/{
		write_int(&builder, e.board_h)
		write_char(&builder, 'x')
		write_int(&builder, e.board_w)

		for tile in e.board {
			write_str(&builder, "\n")
			if tile.card == NO_STRING {
				// card was taken
				write_str(&builder, "none")
			} else if tile.owner == owner {
				// owner is trying to take it
				write_str(&builder, "my ")
				write_str(&builder, e.hash_map[tile.card])
			} else if tile.owner == NO_STRING {
				write_str(&builder, "down")
			} else {
				// there is an owner, just not you
				write_str(&builder, "up ")
				write_str(&builder, e.hash_map[tile.card])
			}
		}
	}
	return str.to_string(builder)
}

board_was_updated :: #force_inline proc(e: ^Effect) {
	if guard(&e.update_lock) {
		e.was_updated = true
		sync.cond_broadcast(&e.update_watch)
	}
}

//@data types
MAX_PLAYERS :: 10
NO_STRING :: 0
Tile :: struct {
	card:      u64,
	owner:     u64,
	watch:     sync.Cond,
	wait_list: [MAX_PLAYERS]u64,
}

// gamestate
//	// board
_board: #soa[]Tile
_board_w, _board_h, _board_size: int
_board_lock: sync.Mutex
_hash_map: map[u64]string

//	// watch
_update_watch: sync.Cond
_update_lock: sync.Mutex
_was_updated: bool

Effect :: struct {
	// gamestate
	//	// board
	board:                        #soa[]Tile,
	board_w, board_h, board_size: int,
	board_lock:                   sync.Mutex,
	hash_map:                     map[u64]string,

	//	// watch
	update_watch:                 sync.Cond,
	update_lock:                  sync.Mutex,
	was_updated:                  bool,
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

	file_data, file_err := os2.read_entire_file_from_path(file, context.allocator)
	if file_err != nil {
		fmt.panicf("Failed to open and read file %v: %v", file, file_err)
	}

	file_lines, split_err := str.split_lines(str.trim_space(cast(string)file_data))
	dimentions := str.split(file_lines[0], "x")
	_board_w = atoi(dimentions[0])
	_board_h = atoi(dimentions[1])

	tile_lines := file_lines[1:]

	_board_size = _board_h * _board_w
	assert(len(tile_lines) == _board_size)
	_board = make_soa_slice(#soa[]Tile, _board_size) // initialize board
	for &tile, i in _board {
		txt_hash := hash(tile_lines[i])
		tile.card = txt_hash
		_hash_map[txt_hash] = tile_lines[i]
	}

	/*
	*	Lock hierarchy:
	*	player > board > watch
	*/

	e := Effect {
		_board,
		_board_w,
		_board_h,
		_board_size,
		_board_lock,
		_hash_map,
		_update_watch,
		_update_lock,
		_was_updated,
	}

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)


	http.route_get(
		&router,
		"/look/(.+)",
		{
			user_data = &e,
			handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
				e := cast(^Effect)h.user_data
				req_arena: mem.Arena
				req_buff: [4096]u8
				mem.arena_init(&req_arena, req_buff[:])
				context.allocator = mem.arena_allocator(&req_arena)


				player_name := req.url_params[0]
				player_id := hash(player_name)

				boardstate: string
				boardstate = gen_board(player_id, e)
				// }

				http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
				http.respond_plain(res, boardstate)

			},
		},
	)
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


			if guard(&e.update_lock) {
				for !e.was_updated {
					sync.cond_wait(&e.update_watch, &e.update_lock)
				}
				e.was_updated = false
			}


			boardstate := gen_board(player_id, e)
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

			from, from_ok := net.percent_decode(req.url_params[1])
			to, to_ok := net.percent_decode(req.url_params[2])
			from_hash := hash(from)
			to_hash := hash(to)
			e.hash_map[to_hash] = str.clone(to, e.hash_map.allocator)

			for &tile_card, i in e.board.card[:e.board_size] {
				_tile := e.board[i]
				if tile_card == from_hash do tile_card = to_hash
			}

			board_was_updated(e)


			boardstate := gen_board(player_id, e)


			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)
		},
	})

	http.route_get(&router, "/flip/(.+)/(.+)", {user_data = &e, handle = handle_flip})

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
				thread_count = os.processor_core_count(),
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


handle_flip :: proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {

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

	write_guard: if guard(&e.board_lock) {

		player_poss := find_player_pos(player_id, e)
		tile := &e.board[tile_pos]

		switch {

		case player_poss[0] != 0 && player_poss[1] != 0:
			// if both exist and are non 0
			tp := player_poss - 1
			tile1 := e.board[tp[0]]
			tile2 := e.board[tp[1]]

			// 3-a
			// if they are the same 2 cards, empty them
			if tile1.card == tile2.card {
				e.board[tp[0]].card, e.board[tp[1]].card = NO_STRING, NO_STRING
				e.board[tp[0]].wait_list = 0
				e.board[tp[1]].wait_list = 0
			} else { 	// free them up
				status = .Conflict
			}
			evacuate_tile(tp[0], e)
			evacuate_tile(tp[1], e)

			board_was_updated(e)
			// the previous 2 choices were handled
			// now act as if that was the first choice
			fallthrough
		// if has no cards
		case player_poss[0] + player_poss[1] == 0:
			// #1-a
			if tile.card == NO_STRING {
				// no card here
				// operations fails and you do nothing
				log.debugf("%s has chosen empty tile", player_name)
				status = .Conflict
				board_was_updated(e)
				break write_guard
			}

			// #1-bc
			if tile.owner != player_id {
				if tile.owner != NO_STRING {
					place_back(&tile.wait_list, player_id)
					// while tile is not evacuated to player_id or it still exists
					for tile.owner != player_id && tile.card != NO_STRING {
						sync.cond_wait(&tile.watch, &e.board_lock)
					}
					if tile.card != NO_STRING {
						status = .Conflict
					}
					break write_guard
				} else {
					// there should be no situation where there is no owner but there is an waitlist
					assert(tile.wait_list == 0)

					e.board[tile_pos].owner = player_id
					log.debugf("%s choose free tile", player_name)

					board_was_updated(e)
					break write_guard
				}
			}


			if tile.owner == player_id {
				internal_error(
					res,
					"there should be no cards owned by player if this is the first choice",
					0,
				)
				return
			}


		// has already 1 tile occupied
		case player_poss[0] * player_poss[1] == 0:
			// #2-a
			if tile.card == NO_STRING {
				// no card here

				// relinquish controll of choices
				old_choice := player_poss[0] + player_poss[1]

				// player pos starts from 1, 0 means empty
				assert(old_choice != 0)

				evacuate_tile(old_choice - 1, e)
				status = .Conflict
				board_was_updated(e)

				log.debugf("%s has chosen empty tile as second choice", player_name)

				break write_guard
			}

			// #2-b
			if tile.owner != NO_STRING {
				old_choice := player_poss[0] + player_poss[1]

				// player pos starts from 1, 0 means empty
				// no evacuation, no adding yourself to the waitlist,
				// you have to cycle the waitlist
				evacuate_tile(old_choice - 1, e)
				status = .Conflict

				log.debugf("%s has chosen owned tile as second choice", player_name)
				board_was_updated(e)

				break write_guard
			}

			// #2-cde
			//if tile.owner == NO_STRING
			e.board[tile_pos].owner = player_id
			log.debugf("%s choose free tile as second tile", player_name)
			board_was_updated(e)
		}
	} // :write_guard

	boardstate := gen_board(player_id, e)

	http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
	http.respond_plain(res, boardstate, status = status)
}
