#+feature global-context
package main

import "base:builtin"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import str "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
write_str :: str.write_string
write_int :: str.write_int
write_char :: str.write_rune

guard_read :: sync.rw_mutex_shared_guard
guard_write :: sync.rw_mutex_guard
guard :: sync.mutex_guard

map_f :: slice.mapper
find :: slice.linear_search

unwrap :: #force_inline proc(something: $T, ok: $D, loc := #caller_location) -> T {
	assert_contextless(ok)
	return something
}

atoi :: proc(num: string) -> int {
	return unwrap(strconv.parse_int(num, 10))
}

import "core:fmt"
import "core:log"

import http "odin-http"


Tile :: struct {
	card:      string,
	owner:     string,
	wait_list: [dynamic]string,
}

Player :: struct {
	id:      string,
	choices: [2][]int,
}


main :: proc() {
	// memory
	// TODO:figure out if you need this even
	_global_allocator: mem.Mutex_Allocator
	@(static) global_allocator: mem.Allocator
	global_allocator = mem.mutex_allocator(&_global_allocator) // defaut heap allocator

	// gamestate
	//	// board
	@(static) board: [][]Tile
	@(static) board_lock: sync.RW_Mutex
	// TODO: initialize board by parsing a txt file
	board = make([][]Tile, 6) // initialize board
	for &row, i in board {
		row = make([]Tile, 4)
	}

	//	// watch
	@(static) update_watch: sync.Cond
	@(static) update_lock: sync.Mutex


	//	// playerstate
	@(static) players: #soa[dynamic]Player
	@(static) player_lock: sync.Mutex
	players = make_soa_dynamic_array(#soa[dynamic]Player) // initiate it with default heap allocator


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
				_, exists := find(players.id[:p_len], player_id)

				if !exists do append_soa_elem(&players, Player{id = player_id})
			}

			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board("")


			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)

		},
		next = &delay_handler,
	})
	http.route_get(&router, "/watch/(.+)", {
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
			log.debug("request", req.url)

			player_id := req.url_params[0]
			if guard(&player_lock) {
				p_len := len(players)
				_, exists := find(players.id[:p_len], player_id)

				if !exists do append_soa_elem(&players, Player{id = player_id})
			}

			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board("")

			log.info("waiting on", update_watch, &update_watch)
			sync.cond_wait(&update_watch, &update_lock)

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)
		},
	})
	http.route_get(&router, "/flip/(.+)/(.+)", {
		handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
			log.debug("request", req.url)

			player_id := req.url_params[0]
			location: []int = map_f(str.split(req.url_params[1], ","), atoi)
			if guard(&player_lock) {
				p_len := len(players)
				idx, exists := find(players.id[:p_len], player_id)

				if !exists {
					player_data := Player {
						id = player_id,
					}
					player_data.choices[0] = location
					append_soa_elem(&players, Player{id = player_id})
				} else {
					player_data := players[idx]
					switch {
					case player_data.choices[0] == nil:
						players[idx].choices[0] = location
					case player_data.choices[1] == nil:
						players[idx].choices[1] = location
					case:

					}
				}
			}


			tile: ^Tile
			if guard_write(&board_lock) do if guard(&player_lock) {
				tile = &(board[location[0]][location[1]])
				switch tile.owner {
				case "":
					tile.owner = player_id
				case player_id:
				case:
					append(&tile.wait_list, player_id)
				}
			}


			boardstate: string
			if guard_read(&board_lock) do boardstate = gen_board("")

			log.debug(boardstate)

			http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
			http.respond_plain(res, boardstate)

			sync.cond_broadcast(&update_watch)
			log.info("Broadcasted to", update_watch, &update_watch)
		},
		next = &delay_handler,
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
