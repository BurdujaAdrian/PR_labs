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
import "core:testing"
import "core:thread"
import "core:time"
import http "odin-http"


@(test)
test_test :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [256]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e
	///

	// checking
	when true {
		fmt.assertf(true, "True is false")
	}
	fmt.println("test_test completed")
}
@(test)
test_not_find_player_pos :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board_size = 3
	e.board = make(#soa[]Tile, 3)
	player_id: u64 = 1
	///

	player_pos := find_player_pos(player_id, e)

	// checking
	when true {
		fmt.assertf(player_pos == 0, "Player positions should be {{0,0}}, %v instead", player_pos)
	}
	fmt.println("test_not_find_player_pos completed")
}

@(test)
test_find_player_pos :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board_size = 3
	e.board = make(#soa[]Tile, 3)
	e.board[0] = {
		owner = 1,
	}
	e.board[1] = {
		owner = 1,
	}
	player_id: u64 = 1
	///

	player_pos := find_player_pos(player_id, e)

	// checking
	when true {
		fmt.assertf(
			player_pos == {1, 2},
			"Player positions should be {{0,1}}, %v instead",
			player_pos,
		)
	}
}

@(test)
test_2prev_same :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 3)
	e.board[0] = {
		card  = 1,
		owner = 1,
	}
	e.board[1] = {
		card  = 1,
		owner = 1,
	}

	player_poss := [2]int{1, 2}
	player_id: u64 = 1
	status := http.Status.OK

	///

	// if both exist and are non 0

	/// original code
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
	///

	// checking
	when true {
		fmt.assertf(
			status == .OK,
			"Status after removing both should be Ok, got %v instead",
			status,
		)

		fmt.assertf(e.board[0].card == NO_STRING, "The first card should be empty")
		fmt.assertf(e.board[1].card == NO_STRING, "The second card should be empty")
	}

	fmt.println("test_2prev_same completed")
}


@(test)
test_rule_1bc :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [256]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	tile: Tile
	player_id: u64
	status := http.Status.OK
	player_name: string
	tile_pos: int
	///

	write_guard: {
		/// Original code
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

		///
	}

	// checking
	when true {
		fmt.assertf(true, "True is false")
	}
	fmt.println("test_test completed")
}
