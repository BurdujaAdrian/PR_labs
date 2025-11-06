package main

import "core:fmt"
import str "core:strings"
import "core:sync"

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
_board_w, _board_h: int
_board_lock: sync.Mutex
_hash_map: map[u64]string

//	// watch
_update_watch: sync.Cond
_update_lock: sync.Mutex
_was_updated: bool

Effect :: struct {
	// gamestate
	//	// board
	board:            #soa[]Tile,
	board_w, board_h: int,
	board_lock:       sync.Mutex,
	hash_map:         map[u64]string,

	//	// watch
	update_watch:     sync.Cond,
	update_lock:      sync.Mutex,
	was_updated:      bool,
}

//@board modifiers
handle_one_prev_choice :: proc(
	player_id: u64,
	player_poss: [2]int,
	tile_pos: int,
	e: ^Effect,
) -> (
	err: Game_err,
) {
	// #2-ab
	if e.board[tile_pos].card == NO_STRING || e.board[tile_pos].owner != NO_STRING {
		// no card here
		old_choice := player_poss[0] + player_poss[1]

		// player pos starts from 1, 0 means empty
		assert(old_choice != 0)

		// relinquish controll of choices
		evacuate_tile(old_choice - 1, e)

		board_was_updated(e)
		return .Conflict
	}


	// #2-cde
	//if tile.owner == NO_STRING
	e.board[tile_pos].owner = player_id
	board_was_updated(e)
	return
}

handle_no_prev_choices :: proc(player_id: u64, tile_pos: int, e: ^Effect) -> (err: Game_err) {

	// #1-a
	if e.board[tile_pos].card == NO_STRING {
		// no card here
		// operations fails and you do nothing
		board_was_updated(e)
		return .Conflict
	}

	// #1-bcd
	if e.board[tile_pos].owner != player_id {
		if e.board[tile_pos].owner != NO_STRING {
			place_back(&e.board[tile_pos].wait_list, player_id)
			// while tile is not evacuated to player_id or it still exists
			for e.board[tile_pos].owner != player_id && e.board[tile_pos].card != NO_STRING {
				fmt.println("Waiting on cond: ", e.board[tile_pos].owner)
				sync.cond_wait(&e.board[tile_pos].watch, &e.board_lock)
			}
			if e.board[tile_pos].card == NO_STRING {
				err = .Conflict
			}
		} else {
			// there should be no situation where there is no owner but there is an waitlist
			assert(e.board[tile_pos].wait_list == 0)

			e.board[tile_pos].owner = player_id

			board_was_updated(e)
		}
	} else {
		fmt.assertf(
			e.board[tile_pos].owner != player_id,
			"there should be no cards owned by player if this is the first choice",
		)
	}

	return
}
handle_2prev_choices :: proc(player_poss: [2]int, e: ^Effect) -> (err: Game_err) {
	tp := player_poss - 1
	tile1 := e.board[tp[0]]
	tile2 := e.board[tp[1]]
	if tile1.card == tile2.card {
		e.board[tp[0]].card = NO_STRING
		e.board[tp[1]].card = NO_STRING
		e.board[tp[0]].wait_list = 0
		e.board[tp[1]].wait_list = 0
	} else {
		err = .Conflict
	}
	evacuate_tile(tp[0], e)
	evacuate_tile(tp[1], e)

	board_was_updated(e)

	return
}

POS_INT_MAX: int : 1 << 63 - 1
//@game helpers
find_player_pos :: proc(player_id: u64, e: ^Effect) -> (res: [2]int) {
	fmt.assertf(len(e.board) < POS_INT_MAX, "Board size: %v >= MAX: %v", len(e.board), POS_INT_MAX)
	for id, i in e.board.owner[:len(e.board)] {
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

	fmt.assertf(pos > -1, "input pos must be positive")

	e.board[pos].owner = pop_front(&e.board[pos].wait_list)
	sync.cond_broadcast(&e.board[pos].watch)
}


board_was_updated :: #force_inline proc(e: ^Effect) {
	if guard(&e.update_lock) {
		e.was_updated = true
		sync.cond_broadcast(&e.update_watch)
	}
}
