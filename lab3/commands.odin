package main

import "base:builtin"
import "base:runtime"
import "core:encoding/csv"
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


//@server helpers
internal_error :: proc(res: ^http.Response, msg: string, err: $E) {
	log.error(msg, err)
	http.headers_set(&res.headers, "Access-Control-Allow-Origin", "*")
	http.body_set_str(res, fmt.aprint(msg, err))
	http.respond_with_status(res, .Internal_Server_Error)
}

Game_err :: enum {
	Conflict,
	INTERNAL,
}

flip :: proc(player_id: u64, tile_pos: int, e: ^Effect) -> (boardstate: string, err: Game_err) {

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
				err = .Conflict
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
				err = .Conflict
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
						err = .Conflict
					}
					break write_guard
				} else {
					// there should be no situation where there is no owner but there is an waitlist
					assert(tile.wait_list == 0)

					e.board[tile_pos].owner = player_id

					board_was_updated(e)
					break write_guard
				}
			}


			if tile.owner == player_id {
				return "there should be no cards owned by player if this is the first choice",
					.INTERNAL
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
				err = .Conflict
				board_was_updated(e)

				break write_guard
			}

			// #2-b
			if tile.owner != NO_STRING {
				old_choice := player_poss[0] + player_poss[1]

				// player pos starts from 1, 0 means empty
				// no evacuation, no adding yourself to the waitlist,
				// you have to cycle the waitlist
				evacuate_tile(old_choice - 1, e)
				err = .Conflict

				board_was_updated(e)

				break write_guard
			}

			// #2-cde
			//if tile.owner == NO_STRING
			e.board[tile_pos].owner = player_id
			board_was_updated(e)
		}
	} // :write_guard

	return look(player_id, e), nil
}


replace :: proc(to, from: string, player_id: u64, e: ^Effect) -> string {

	from_hash := hash(from)
	to_hash := hash(to)
	e.hash_map[to_hash] = str.clone(to, e.hash_map.allocator)

	for &tile_card, i in e.board.card[:e.board_size] {
		_tile := e.board[i]
		if tile_card == from_hash do tile_card = to_hash
	}
	board_was_updated(e)

	return look(player_id, e)
}

watch :: proc(player_id: u64, e: ^Effect) -> string {
	if guard(&e.update_lock) {
		for !e.was_updated {
			sync.cond_wait(&e.update_watch, &e.update_lock)
		}
		e.was_updated = false
	}

	return look(player_id, e)
}

look :: proc(owner: u64, e: ^Effect, loc := #caller_location) -> string {
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
