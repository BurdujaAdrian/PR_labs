#+feature global-context
package main

import "base:builtin"
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

gen_board :: proc(owner: string) -> string {
	builder: str.Builder

	write_int(&builder, len(board[0]))
	write_char(&builder, 'x')
	write_int(&builder, len(board))

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
				write_str(&builder, "\n")
			} else if tile.owner == "" {
				write_str(&builder, "down\n")
				continue inner
			} else {
				// there is an owner, just not you
				write_str(&builder, "up ")
				write_str(&builder, tile.card)
			}
		}

	}

	return str.to_string(builder)
}

evacuate_tile :: proc(pos: [2]int) {
	// if pos is <NONE>, do nothing
	if pos == -1 do return

	tile := &board[pos.x][pos.y]
	tile.owner = ""
	if len(tile.wait_list) > 0 {
		tile.owner = pop_front(&tile.wait_list)
	}
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


//	// playerstate
players: #soa[dynamic]Player
player_lock: sync.Mutex

main :: proc() {

	global_allocator = context.allocator // defaut heap allocator

	// TODO: initialize board by parsing a txt file
	board = make([][]Tile, 6) // initialize board
	for &row, i in board {
		row = make([]Tile, 4)
		for &tile in &row {
			tile.wait_list, _ = make([dynamic]string)
		}
	}

	players = make_soa_dynamic_array(#soa[dynamic]Player) // initiate it with default heap allocator
	/*
	*	Lock hierarchy:
	*	player > board
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

			log.debug("request", req.url, " on thread:", sync.current_thread_id())

			player_id := req.url_params[0]
			if guard(&player_lock) {
				p_len := len(players)
				idx, exists := find(players.id[:p_len], player_id)

				if !exists do if _, err := append_soa_elem(&players, Player{id = player_id}); err != nil {
					internal_error(res, "Allocation error in /watch, failed to allocate new player", err)
					return
				}
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

			log.debug("request", req.url)

			player_id := req.url_params[0]
			if guard(&player_lock) {
				p_len := len(players)
				idx, exists := find(players.id[:p_len], player_id)

				if !exists do if _, err := append_soa_elem(&players, Player{id = player_id}); err != nil {
					internal_error(res, "Allocation error in /watch, failed to allocate new player", err)
					return
				}
			}

			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board("")

			log.info("waiting on", update_watch)
			sync.cond_wait(&update_watch, &update_lock)

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)
		},
	})

	http.route_get(&router, "/replace/(.+)/(.+)/(.+)", {
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
			log.debug("request", req.url)

			player_id := req.url_params[0]
			from := req.url_params[1]
			to := req.url_params[2]

			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board("")

			log.debug(boardstate)

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)

			sync.cond_broadcast(&update_watch)
			log.info("Broadcasted to", update_watch, &update_watch)
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

	log.debug("parsing request further for ", req.url)

	player_id := req.url_params[0]
	loc_str, _ := str.split(req.url_params[1], ",")

	location: [2]int
	location[0] = atoi(loc_str[0])
	location[1] = atoi(loc_str[1])

	in_wait_list: bool = true
	// TODO: check if this is sane, if finished
	for in_wait_list { 	// loop while in the wait_list
		in_wait_list = false // assume will not be in waitlist
		log.debugf("update players %s state on flip", player_id)
		had_matching: bool
		if guard(&player_lock) {
			p_len := len(players)
			idx, exists := find(players.id[:p_len], player_id)

			if !exists {
				log.debug("append new player", player_id)
				player_data := Player {
					id      = player_id,
					choices = {location, -1},
				}
				if _, err := append_soa_elem(&players, player_data); err != nil {
					internal_error(res, "Allocation error in /flip, append new player:", err)
					return
				}
			}

			log.debugf(
				"Attempting to update board based on state %v of %s",
				players[idx],
				player_id,
			)
			if guard_write(&board_lock) {

				log.debug("update player ", player_id)
				tile := &board[location[0]][location[1]]

				if tile.card == "" { 	// if card is non  existant
					log.debugf("Player %s flipped non-existent card", player_id)
					old_choices := players[idx].choices
					players[idx].choices = -1

					evacuate_tile(old_choices[0])
					evacuate_tile(old_choices[1])

				} else if tile.owner == player_id { 	// if card is occupied by me

					log.debugf("Player %s flipped card they already controlled ", player_id)
					old_choices := players[idx].choices
					players[idx].choices = -1

					evacuate_tile(old_choices[0])
					evacuate_tile(old_choices[1])

				} else if tile.owner != "" {
					log.debugf(
						"Player %s flipped card that is already controlled by %s",
						player_id,
						tile.owner,
					)

					append(&tile.wait_list, player_id)
					// PERF: redundant check
				} else if tile.owner == "" do switch {

				case players[idx].choices[0] == -1:
					log.debugf("Player's %s first choice", player_id)
					players[idx].choices = {location, -1}

					log.debugf("Tile %v-%v(%v) captured by player %s", location[0], location[1], tile, player_id)
					tile.owner = player_id

				case players[idx].choices[1] == -1:
					log.debugf("Players %s second choice", player_id)
					players[idx].choices[1] = location

					log.debugf("Tile %v-%v(%v) captured by player %s", location[0], location[1], tile, player_id)
					tile.owner = player_id
				case:
					log.debugf("Player's %s third choice", player_id)
					old_choice := players[idx].choices
					players[idx].choices = {location, -1}

					evacuate_tile(old_choice[0])
					evacuate_tile(old_choice[0])

					log.debugf("Tile %v-%v(%v) captured by player %s", location[0], location[1], tile, player_id)
					tile.owner = player_id
				}
				else {
					// PERF: tail of redundant check
					internal_error(res, "how", 0)
					return
				}

			}
		}
		// operation finished succesfully, exit out of the loop
	}

	boardstate: string
	if guard_read(&board_lock) do boardstate = gen_board("")

	log.debug(boardstate)

	sync.cond_broadcast(&update_watch)
	log.info("Broadcasted to", update_watch, &update_watch)

	http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
	http.respond_plain(res, boardstate)
}
