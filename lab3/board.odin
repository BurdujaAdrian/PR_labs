package main

import "core:fmt"
import "core:log"
import "core:os/os2"
import str "core:strings"
import "core:sync"

guard :: sync.mutex_guard

write_str :: str.write_string
write_int :: str.write_int
write_char :: str.write_rune

//@data types
MAX_PLAYERS :: 10
NO_STRING :: 0
Tile :: struct {
	card:       u64,
	owner:      u64,
	flipped_by: u64,
	watch:      sync.Cond `fmt:"-"`,
	wait_list:  [MAX_PLAYERS]u64 `fmt:"-"`,
}

pop_front :: #force_inline proc(list: ^[MAX_PLAYERS]u64) -> (front: u64) {
	front = list[0]
	#unroll for i in 0 ..< MAX_PLAYERS - 1 {
		list[i] = list[i + 1]
	}
	return
}

flip_free_facedown :: #force_inline proc(tile_id: int, e: ^Effect) {
	// if owner is 0, it will go facedown, else it becomes flipped by whoever the owner is
	e.board[tile_id].flipped_by = e.board[tile_id].owner
}


board_is_empty :: proc(e: ^Effect) -> bool {
	for card in e.board.card[:len(e.board)] {
		if card != NO_STRING do return false
	}

	return true
}

place_back :: proc {
	place_back_tile,
}

place_back_tile :: #force_inline proc(list: ^[MAX_PLAYERS]u64, p_id: u64) {
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

Game_err :: enum {
	Ok,
	Conflict,
}


// - any player doesn't have more then 2 previously controlled tiles
// - Any tile with an owner must be flipped with an owner
// - A tile without an owner should have an empty wait list
check_rep :: #force_inline proc(e: ^Effect) {
	for tile, i in e.board {
		sync.lock(&e.board_lock)
		defer sync.unlock(&e.board_lock)

		if tile.card == NO_STRING {
			// tiles with no card have no invarients
			continue
		}

		if tile.owner != NO_STRING {
			find_player_pos(tile.owner, e)


			fmt.assertf(
				tile.flipped_by == tile.owner,
				"%v %v with an owner must be flipped with an owner %v, not %v",
				tile,
				i,
				tile.owner,
				tile.flipped_by,
			)

			continue
		}

		// if tile.owner == NO_STRING
		fmt.assertf(
			tile.wait_list == 0,
			"A tile without an owner should have an empty wait list, not",
			tile.wait_list,
		)

	}
}


flip_tile :: #force_inline proc(player_id: u64, tile_pos: int, e: ^Effect) -> (err: Game_err) {
	defer board_was_updated(e)
	write_guard: if guard(&e.board_lock) {

		players_owned, players_flipped := find_player_pos(player_id, e)
		tile := &e.board[tile_pos]

		tiles_flipped := players_flipped - 1
		tiles_owned := players_owned - 1

		switch {

		// if both exist and are non 0
		case players_owned[0] != 0 && players_owned[1] != 0:
			// 3-a
			// if they are the same 2 cards, empty them
			tile1 := e.board[tiles_owned[0]]
			tile2 := e.board[tiles_owned[1]]
			fmt.assertf(
				tile1.card == tile2.card,
				"The only time a player owns 2 cards is when they get a match",
			)
			e.board[tiles_owned[0]].card = NO_STRING
			e.board[tiles_owned[1]].card = NO_STRING
			relinquish_tile(tiles_owned[0], e)
			relinquish_tile(tiles_owned[1], e)


			// the previous 2 choices were handled
			// now act as if that was the first choice
			fallthrough
		// if has no cards
		case players_owned[0] + players_owned[1] == 0:
			if tiles_flipped[0] > -1 do flip_free_facedown(tiles_flipped[0], e)
			if tiles_flipped[1] > -1 do flip_free_facedown(tiles_flipped[1], e)
			// #1-a
			if tile.card == NO_STRING {
				// no card here
				// operations fails and you do nothing
				return .Conflict
			}

			// #1-bcd
			fmt.assertf(
				tile.owner != player_id,
				"there should be no cards owned by player if this is the first choice",
			)

			if tile.owner != NO_STRING {
				place_back(&tile.wait_list, player_id)
				// while tile is not evacuated to player_id or it still exists

				wait_loop: for {
					when ODIN_DEBUG do fmt.println(player_id, "is waiting on", tile)
					sync.cond_wait(&tile.watch, &e.board_lock)

					if tile.owner == player_id {
						when ODIN_DEBUG do fmt.println(player_id, "has taken controll over", tile)
						break wait_loop
					}
					if tile.card == NO_STRING {
						when ODIN_DEBUG do fmt.println(player_id, "'s tile got deleted: ", tile)
						err = .Conflict
						break wait_loop
					}
				}

			} else {
				tile.owner = player_id
				tile.flipped_by = player_id
			}

		// has already 1 tile occupied
		case players_owned[0] * players_owned[1] == 0:
			// #2-a
			if tile.card == NO_STRING {
				// no card here
				old_choice := players_owned[0] + players_owned[1]

				// player pos starts from 1, 0 means empty
				assert(old_choice != 0)

				relinquish_tile(old_choice - 1, e)


				return .Conflict
			}

			// #2-b
			if tile.owner != NO_STRING {
				// no card here
				old_choice := tiles_owned[0] + tiles_owned[1] + 1

				relinquish_tile(old_choice, e)

				return .Conflict
			}

			// #2-cde
			//if tile.owner == NO_STRING
			tile.owner = player_id
			tile.flipped_by = player_id

			prev_tile_pos := players_owned[0] + players_owned[1] - 1
			prev_tile := e.board[prev_tile_pos]

			if tile.card != prev_tile.card {
				relinquish_tile(prev_tile_pos, e)
				relinquish_tile(tile_pos, e)

				err = .Conflict
			}
		}
	} // :write_guard

	check_rep(e)

	return
}

board_map :: #force_inline proc(to, from: string, e: ^Effect) -> Game_err {
	if str.contains_any(to, " \r\n") do return .Conflict
	from_hash := hash(from)
	e.hash_map[from_hash] = str.clone(to, e.hash_map.allocator)
	board_was_updated(e)
	check_rep(e)
	return .Ok
}
board_watch :: #force_inline proc(e: ^Effect) {
	if guard(&e.update_lock) {
		for !e.was_updated do sync.cond_wait(&e.update_watch, &e.update_lock)
		e.was_updated = false
	}
	check_rep(e)
}

board_look :: #force_inline proc(player_id: u64, e: ^Effect, loc := #caller_location) -> string {
	fmt.assertf(
		player_id != NO_STRING,
		"the player_id when calling look board should not be \"\"",
		loc = loc,
	)
	builder: str.Builder

	check_rep(e)

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
			} else if tile.flipped_by == NO_STRING && tile.owner == NO_STRING {
				write_str(&builder, "down")
			} else if tile.owner == player_id {
				// owner is trying to take it
				write_str(&builder, "my ")
				write_str(&builder, e.hash_map[tile.card])
			} else {
				// there is an owner, just not you
				write_str(&builder, "up ")
				write_str(&builder, e.hash_map[tile.card])
			}
		}
	}
	return str.to_string(builder)
}

parse_board :: proc(
	file: string,
) -> (
	board_w, board_h: int,
	hash_map: map[u64]string,
	board: #soa[]Tile,
) {

	file_data, file_err := os2.read_entire_file_from_path(file, context.allocator)

	if file_err != nil {
		fmt.panicf("Failed to open and read file %v: %v", file, file_err)
	}
	file_lines, split_err := str.split_lines(str.trim_space(cast(string)file_data))
	dimentions := str.split(file_lines[0], "x")
	board_w = atoi(dimentions[0])
	board_h = atoi(dimentions[1])

	tile_lines := file_lines[1:]

	board_size := board_h * board_w
	fmt.assertf(len(tile_lines) == board_size, "%v != %v", len(tile_lines), board_size)
	board = make_soa_slice(#soa[]Tile, board_size) // initialize board
	for &tile, i in board {
		fmt.assertf(
			str.count(tile_lines[i], " ") == 0,
			"Any tile should not have any empty spaces as string",
		)
		txt_hash := hash(tile_lines[i])
		tile.card = txt_hash
		hash_map[txt_hash] = tile_lines[i]
	}
	return
}


POS_INT_MAX: int : 1 << 63 - 1
//@game helpers
find_player_pos :: proc(
	player_id: u64,
	e: ^Effect,
	loc := #caller_location,
) -> (
	owned: [2]int,
	flipped: [2]int,
) {
	fmt.assertf(len(e.board) < POS_INT_MAX, "Board size: %v >= MAX: %v", len(e.board), POS_INT_MAX)
	loop: for tile, i in e.board {

		if tile.card == NO_STRING {
			// tiles without cards do not contain info
			continue loop
		}
		id := tile.owner
		if player_id == id {
			fmt.assertf(
				flipped[0] * flipped[1] == 0,
				"Any player should not have more than 2 cards flipped at a time",
				loc = loc,
			)
			fmt.assertf(
				owned[0] * owned[1] == 0,
				"Any player should not have more than 2 cards owned at a time",
				loc = loc,
			)

			switch {
			case owned[0] == 0:
				owned[0] = i + 1
				flipped[0] = i + 1
			case owned[1] == 0:
				owned[1] = i + 1
				flipped[1] = i + 1
			}
			continue loop
		}

		id = tile.flipped_by
		if player_id == id {


			fmt.assertf(
				flipped[0] * flipped[1] == 0,
				"Any player should not have more than 2 cards flipped at a time",
				loc = loc,
			)
			switch {
			case flipped[0] == 0:
				flipped[0] = i + 1
			case flipped[1] == 0:
				flipped[1] = i + 1
			}
		}
	}
	return
}


relinquish_tile :: proc(pos: int, e: ^Effect, loc := #caller_location) {

	fmt.assertf(pos > -1, "input pos must be positive", loc = loc)

	e.board[pos].owner = pop_front(&e.board[pos].wait_list)
	if e.board[pos].owner != NO_STRING {e.board[pos].flipped_by = e.board[pos].owner}
	sync.cond_broadcast(&e.board[pos].watch)
}


board_was_updated :: #force_inline proc(e: ^Effect) {
	if guard(&e.update_lock) {
		e.was_updated = true
		sync.cond_broadcast(&e.update_watch)
	}
}
