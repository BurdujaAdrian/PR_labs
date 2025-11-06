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
	Ok,
	Conflict,
}

flip :: proc(player_id: u64, tile_pos: int, e: ^Effect) -> (boardstate: string, err: Game_err) {

	write_guard: if guard(&e.board_lock) {

		player_poss := find_player_pos(player_id, e)
		tile := &e.board[tile_pos]

		switch {

		// if both exist and are non 0
		case player_poss[0] != 0 && player_poss[1] != 0:
			// 3-a
			// if they are the same 2 cards, empty them
			err = handle_2prev_choices(player_poss, e)
			// the previous 2 choices were handled
			// now act as if that was the first choice
			fallthrough
		// if has no cards
		case player_poss[0] + player_poss[1] == 0:
			// rule #1-abc, blocking
			err = handle_no_prev_choices(player_id, tile_pos, e)

		// has already 1 tile occupied
		case player_poss[0] * player_poss[1] == 0:
			// rule #2-abcde
			err = handle_one_prev_choice(player_id, player_poss, tile_pos, e)
		}
	} // :write_guard

	return look(player_id, e), .Ok
}


replace :: proc(to, from: string, player_id: u64, e: ^Effect) -> string {

	from_hash := hash(from)
	e.hash_map[from_hash] = str.clone(to, e.hash_map.allocator)

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

look :: proc(player_id: u64, e: ^Effect, loc := #caller_location) -> string {
	fmt.assertf(
		player_id != NO_STRING,
		"the player_id when calling look board should not be \"\"",
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
			} else if tile.owner == player_id {
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
