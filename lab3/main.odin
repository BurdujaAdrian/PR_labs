#+feature global-context
package main

import "base:builtin"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
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
	assert_contextless(ok)
	return something
}

atoi :: proc(num: string) -> int {
	return unwrap(strconv.parse_int(num, 10))
}


//@server helpers
internal_error :: proc(res: ^http.Response, msg: string, err: $E) {
	log.error(msg, err)
	http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
	http.body_set_str(res, fmt.aprint(msg, err))
	http.respond_with_status(res, .Internal_Server_Error)
}


//@data types
Tile :: struct {
	card:      string,
	owner:     string,
	wait_list: [dynamic]string,
}

Player :: struct {
	id:      string,
	choices: [2][2]int,

	// only 2 states can persist: no choice or only 1 choice
}

GameErr :: enum {
	THREE_CHOICES,
	NO_SECOND_CHOICE,
}

gen_board :: proc(owner: string, loc := #caller_location) -> string {
	fmt.assertf(owner != "", "the owner when calling gen board should not be \"\"", loc = loc)
	builder: str.Builder

	write_int(&builder, len(board))
	write_char(&builder, 'x')
	write_int(&builder, len(board[0]))

	for row in board {
		inner: for tile in row {
			write_str(&builder, "\n")
			if tile.card == "" {
				// card was taken
				write_str(&builder, "none")
			} else if tile.owner == owner {
				// owner is trying to take it
				write_str(&builder, "my ")
				write_str(&builder, tile.card)
				// write_str(&builder, "|")
				// write_str(&builder, tile.owner)
			} else if tile.owner == "" {
				write_str(&builder, "down")
			} else {
				// there is an owner, just not you
				write_str(&builder, "up ")
				write_str(&builder, tile.card)
				// write_str(&builder, "|")
				// write_str(&builder, tile.owner)
			}
		}

	}

	return str.to_string(builder)
}

evacuate_tile :: proc(pos: [2]int) {
	// if pos is <NONE>, do nothing
	if pos == -1 do return

	tile := &board[pos.x][pos.y]
	delete(tile.owner, global_allocator)
	tile.owner = ""

}

// memory
global_allocator: mem.Allocator

// gamestate
//	// board
board: [][]Tile
board_lock: sync.RW_Mutex

//	// watch
update_watch: sync.Cond
update_lock: sync.Mutex
was_updated: bool

board_was_updated :: #force_inline proc() {
	if guard(&update_lock) {
		was_updated = true
		sync.cond_broadcast(&update_watch)
	}
}

//	// playerstate
players: #soa[dynamic]Player
player_lock: sync.Mutex

main :: proc() {

	global_allocator = context.allocator // defaut heap allocator

	// TODO: initialize board by parsing a txt file
	board = make([][]Tile, 6) // initialize board
	for &row, i in &board {
		row = make([]Tile, 4)
		for &tile in &row {
			tile.wait_list, _ = make([dynamic]string, global_allocator)
			tile.card = "A" if i % 2 == 0 else "B" // for now it's all A
			tile.owner = ("")
		}
	}

	players = make_soa_dynamic_array(#soa[dynamic]Player) // initiate it with default heap allocator
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


			player_id := req.url_params[0]
			if guard(&player_lock) {
				p_len := len(players)
				idx, exists := find(players.id[:p_len], player_id)

				if !exists do append_soa_elem(&players, Player{id = player_id, choices = -1})
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


			player_id := req.url_params[0]
			if guard(&player_lock) {
				p_len := len(players)
				idx, exists := find(players.id[:p_len], player_id)

				if !exists do append_soa_elem(&players, Player{id = player_id, choices = -1})
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

	http.route_get(
		&router,
		"/replace/(.+)/(.+)/(.+)",
		{
			handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {

				req_arena: mem.Arena
				req_buff: [4096]u8
				mem.arena_init(&req_arena, req_buff[:])
				context.allocator = mem.arena_allocator(&req_arena)

				player_id := req.url_params[0]
				from := req.url_params[1]
				to := req.url_params[2]
				// TODO: implement replace

				board_was_updated()


				boardstate: string
				if guard_read(&board_lock) do boardstate = gen_board(player_id)


				http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
				http.respond_plain(res, boardstate)
			},
		},
	)

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


	player_id := req.url_params[0]
	loc_str, _ := str.split(req.url_params[1], ",")

	location: [2]int
	location[0] = atoi(loc_str[0])
	location[1] = atoi(loc_str[1])

	in_wait_list: bool
	loop: for {
		pguard: if guard(&player_lock) {

			p_len := len(players)
			idx, exists := find(players.id[:p_len], player_id)

			if !exists {
				new_player := Player {
					id      = player_id,
					choices = -1,
				}

				append_soa_elem(&players, new_player)

				p_len = len(players)
				idx, exists = find(players.id[:p_len], player_id)

				assert(exists)

			}

			write_guard: if guard_write(&board_lock) {
				inner_loop: for {

					tile := &board[location[0]][location[1]]
					switch {

					case players[idx].choices[0] == -1:
						// #1-a
						if tile.card == "" {
							// no card here
							// operations fails and you do nothing
							assert(len(tile.wait_list) == 0)
							board_was_updated()
							break loop
						}

						// #1-bc
						if tile.owner == "" {
							if in_wait_list {
								assert(len(tile.wait_list) > 0)
								if tile.wait_list[0] == player_id {
									me := pop_front(&tile.wait_list)
									delete(me, global_allocator)
									in_wait_list = false
								}
							}
							// free card
							players[idx].choices = {location, -1}

							tile.owner = str.clone(player_id, global_allocator)

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
							append_elem(&tile.wait_list, str.clone(player_id, global_allocator))
							assert(len(tile.wait_list) <= len(players))
							// the choice is not saved, as it's not allowed yet
							// players[idx].choices = {location, -1}
						}
						continue loop


					case players[idx].choices[1] == -1:
						// #2-a
						if tile.card == "" {
							// no card here

							// relinquish controll of choices
							old_choice := players[idx].choices[0]
							players[idx].choices = -1

							evacuate_tile(old_choice)
							board_was_updated()

							break loop
						}

						// #2-b
						if tile.owner != "" {
							old_choice := players[idx].choices
							players[idx].choices = -1

							evacuate_tile(old_choice[0])
							// i wasn't added to waitlist, i shouldn't touch it either

							board_was_updated()
							// PERF: sanity check
							when ODIN_DEBUG do if old_choice[1] != -1 {
								internal_error(res, "second tile should not exist", 0)
								return
							}
							break loop
						}

						//if tile.owner == ""
						// #2-e
						players[idx].choices[1] = location
						prev_location := players[idx].choices[0]

						tile1 := board[location[0]][location[1]]
						tile2 := board[prev_location[0]][prev_location[1]]

						// if tile1.card != tile2.card {
						// 	evacuate_tile(location)
						// 	evacuate_tile(prev_location)
						//
						// 	board_was_updated()
						//
						// 	// reset players choices
						// 	players[idx].choices = -1
						//
						// 	break loop
						// }
						// #2-cd
						tile.owner = str.clone(player_id, global_allocator)
						board_was_updated()

						break loop
					case:
						old_choices := players[idx].choices
						players[idx].choices = -1

						evacuate_tile(old_choices[0])
						evacuate_tile(old_choices[1])

						board_was_updated()

						tile1 := &board[old_choices[0][0]][old_choices[0][1]]
						tile2 := &board[old_choices[1][0]][old_choices[1][1]]

						// 3-a
						// if they are the same 2 cards, free them
						if tile1.card == tile2.card {
							log.debug("tile1 before cleanup", tile1, player_id)
							log.debug("tile2 before cleanup", tile2, player_id)

							tile1.card, tile2.card = "", ""

							delete(tile1.owner, global_allocator)
							delete(tile2.owner, global_allocator)
							tile1.owner, tile.owner = "", ""

							clear_dynamic_array(&tile1.wait_list)
							clear_dynamic_array(&tile2.wait_list)

							fmt.assertf(
								len(tile1.wait_list) == 0,
								"tile1 doesnt check out:%v\nfor %s",
								tile1,
								player_id,
							)
							fmt.assertf(
								len(tile2.wait_list) == 0,
								"tile2 doesnt check out:%v\nfor %s",
								tile2,
								player_id,
							)

							log.debug("tile1 at was deleted:", tile1, player_id)
							log.debug("tile2 at was deleted:", tile2, player_id)

							assert(tile1.wait_list.allocator == global_allocator)
							assert(tile2.wait_list.allocator == global_allocator)

							board_was_updated()
						} else {
							evacuate_tile(old_choices[0])
							evacuate_tile(old_choices[1])

							board_was_updated()
						}

						// the previous 2 choices were handled
						// now act as if that was the first choice
						continue inner_loop
					}
				} // :inner_loop
			} // :write_guard
		} // :pguard
		time.sleep(1 * time.Millisecond)
	} // :loop

	boardstate: string
	if guard_read(&board_lock) do boardstate = gen_board(player_id)

	http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
	http.respond_plain(res, boardstate)
}
