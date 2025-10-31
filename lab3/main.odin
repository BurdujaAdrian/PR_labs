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

guard_read :: sync.rw_mutex_shared_guard
guard_write :: sync.rw_mutex_guard
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

find_player_pos :: proc(player_id: u64) -> (res: [2]int) {
	for id, i in board.owner[:board_size] {
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

evacuate_tile :: proc(pos: int) -> (old_tile: Tile) {
	// if pos is <NONE>, do nothing
	if pos == -1 do return

	old_tile = board[pos]
	board[pos].owner = pop_front(&board[pos].wait_list)

	return
}

gen_board :: proc(owner: u64, loc := #caller_location) -> string {
	fmt.assertf(
		owner != NO_STRING,
		"the owner when calling gen board should not be \"\"",
		loc = loc,
	)
	builder: str.Builder

	write_int(&builder, board_h)
	write_char(&builder, 'x')
	write_int(&builder, board_w)

	for tile in board {
		write_str(&builder, "\n")
		if tile.card == NO_STRING {
			// card was taken
			write_str(&builder, "none")
		} else if tile.owner == owner {
			// owner is trying to take it
			write_str(&builder, "my ")
			write_str(&builder, hash_map[tile.card])
		} else if tile.owner == NO_STRING {
			write_str(&builder, "down")
		} else {
			// there is an owner, just not you
			write_str(&builder, "up ")
			write_str(&builder, hash_map[tile.card])
		}
	}
	return str.to_string(builder)
}

board_was_updated :: #force_inline proc() {
	if guard(&update_lock) {
		was_updated = true
		sync.cond_broadcast(&update_watch)
	}
}

//@data types
MAX_PLAYERS :: 10
NO_STRING :: 0
Tile :: struct {
	card:      u64,
	owner:     u64,
	wait_list: [MAX_PLAYERS]u64,
}

// gamestate
//	// board
board: #soa[]Tile
board_w, board_h, board_size: int
board_lock: sync.RW_Mutex
hash_map: map[u64]string

//	// watch
update_watch: sync.Cond
update_lock: sync.Mutex
was_updated: bool


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
	board_w = atoi(dimentions[0])
	board_h = atoi(dimentions[1])

	tile_lines := file_lines[1:]

	board_size = board_h * board_w
	assert(len(tile_lines) == board_size)
	board = make_soa_slice(#soa[]Tile, board_size) // initialize board
	for &tile, i in board {
		txt_hash := hash(tile_lines[i])
		tile.card = txt_hash
		hash_map[txt_hash] = tile_lines[i]
	}

	/*
	*	Lock hierarchy:
	*	player > board > watch
	*/


	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	delay_handler := http.Handler {
		handle = proc(_: ^http.Handler, _: ^http.Request, _: ^http.Response) {
			time.sleep(100 * time.Millisecond)
		},
	}

	http.route_get(&router, "/look/(.+)", {
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
			req_arena: mem.Arena
			req_buff: [4096]u8
			mem.arena_init(&req_arena, req_buff[:])
			context.allocator = mem.arena_allocator(&req_arena)


			player_name := req.url_params[0]
			player_id := hash(player_name)
			if !(player_id in hash_map) {
				hash_map[player_id] = player_name
			}

			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board(player_id)


			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)

		},
		next = &delay_handler,
	})
	http.route_get(&router, "/watch/(.+)", {
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
			req_arena: mem.Arena
			req_buff: [4096]u8
			mem.arena_init(&req_arena, req_buff[:])
			context.allocator = mem.arena_allocator(&req_arena)


			player_name := req.url_params[0]
			player_id := hash(player_name)
			if !(player_id in hash_map) {
				hash_map[player_id] = player_name
			}


			if guard(&update_lock) {
				for !was_updated {
					sync.cond_wait(&update_watch, &update_lock)
				}
				was_updated = false
			}


			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board(player_id)
			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)
		},
	})

	http.route_get(&router, "/replace/(.+)/(.+)/(.+)", {
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {

			req_arena: mem.Arena
			req_buff: [4096]u8
			mem.arena_init(&req_arena, req_buff[:])
			context.allocator = mem.arena_allocator(&req_arena)

			player_name := req.url_params[0]
			player_id := hash(player_name)
			if !(player_id in hash_map) {
				hash_map[player_id] = player_name
			}

			from, from_ok := net.percent_decode(req.url_params[1])
			to, to_ok := net.percent_decode(req.url_params[2])
			from_hash := hash(from)
			to_hash := hash(to)
			hash_map[to_hash] = str.clone(to, hash_map.allocator)

			for &tile_card, i in board.card[:board_size] {
				_tile := board[i]
				if tile_card == from_hash do tile_card = to_hash
			}

			board_was_updated()


			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board(player_id)


			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)
		},
	})

	http.route_get(&router, "/flip/(.+)/(.+)", {handle = handle_flip, next = &delay_handler})

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
				thread_count = os.processor_core_count() / 2 - 1,
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
handle_flip :: proc(_: ^http.Handler, req: ^http.Request, res: ^http.Response) {

	req_arena: mem.Arena
	req_buff: [4096]u8
	mem.arena_init(&req_arena, req_buff[:])
	context.allocator = mem.arena_allocator(&req_arena)


	player_name := req.url_params[0]
	player_id := hash(player_name)
	if !(player_id in hash_map) {
		hash_map[player_id] = player_name
	}
	loc_str, _ := str.split(req.url_params[1], ",")

	tile_pos: int = atoi(loc_str[0]) * board_w + atoi(loc_str[1])

	in_wait_list: bool
	loop: for {
		write_guard: if guard_write(&board_lock) {

			inner_loop: for {

				player_poss := find_player_pos(player_id)
				tile := &board[tile_pos]
				switch {

				// if has no cards
				case player_poss[0] + player_poss[1] == 0:
					// #1-a
					if tile.card == NO_STRING {
						// no card here
						// operations fails and you do nothing
						board_was_updated()
						break loop
					}

					// #1-bc
					if tile.owner == NO_STRING {
						if in_wait_list {
							if tile.wait_list[0] == player_id {
								pop_front(&board[tile_pos].wait_list)
								in_wait_list = false
							}
						}
						// free card

						board[tile_pos].owner = player_id

						board_was_updated()
						break loop
					}

					if tile.owner == player_id {
						internal_error(
							res,
							"there should be no cards owned by player if this is the first choice",
							0,
						)
						return
					}

					// tile.owner != player_id != ""

					// #1-d
					if !in_wait_list {
						in_wait_list = true
						place_back(&board[tile_pos].wait_list, player_id)
						// the choice is not saved, as it's not allowed yet
					}
					continue loop


				// has already 1 tile occupied
				case player_poss[0] * player_poss[1] == 0:
					// #2-a
					if tile.card == NO_STRING {
						// no card here

						// relinquish controll of choices
						old_choice := player_poss[0] + player_poss[1]

						// player pos starts from 1, 0 means empty
						assert(old_choice != 0)

						evacuate_tile(old_choice - 1)
						board_was_updated()

						break loop
					}

					// #2-b
					if tile.owner != NO_STRING {
						old_choice := player_poss[0] + player_poss[1]

						// player pos starts from 1, 0 means empty
						evacuate_tile(old_choice - 1)
						// i wasn't added to waitlist, i shouldn't touch it either

						board_was_updated()

						break loop
					}

					//if tile.owner == ""
					// #2-cde
					board[tile_pos].owner = player_id
					board_was_updated()

					break loop
				case:
					// if both exist and are non0
					tile1 := evacuate_tile(player_poss[0] - 1)
					tile2 := evacuate_tile(player_poss[1] - 1)

					board_was_updated()

					// 3-a
					// if they are the same 2 cards, free them
					if tile1.card == tile2.card {
						tp := player_poss - 1
						board[tp[0]].card, board[tp[1]].card = NO_STRING, NO_STRING
						board[tp[0]].owner, board[tp[1]].owner = NO_STRING, NO_STRING
						board[tp[0]].wait_list = 0
						board[tp[1]].wait_list = 0

						board_was_updated()
					} else {
						evacuate_tile(player_poss[0] - 1)
						evacuate_tile(player_poss[1] - 1)
						board_was_updated()
					}

					// the previous 2 choices were handled
					// now act as if that was the first choice
					continue inner_loop
				}
			} // :inner_loop
		} // :write_guard
		time.sleep(1 * time.Millisecond)
	} // :loop

	boardstate: string
	if guard_read(&board_lock) do boardstate = gen_board(player_id)

	http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
	http.respond_plain(res, boardstate)
}
