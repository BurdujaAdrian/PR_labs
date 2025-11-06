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


board_was_updated :: #force_inline proc(e: ^Effect) {
	if guard(&e.update_lock) {
		e.was_updated = true
		sync.cond_broadcast(&e.update_watch)
	}
}
