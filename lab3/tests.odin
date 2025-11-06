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
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 2)

//odinfmt: disable
// modify board 
//odinfmt: enable

	player_id: u64 = 1
	player_poss := [2]int{1, 0}
	err: Game_err
	tile_pos := 1
	///

	///origial code
	///

	// checking
	{
		fmt.assertf(true, "True is false")
	}
	fmt.println("test_test completed")
}

@(test)
test_evacuate :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 4)
//odinfmt: disable
	e.board[0] = Tile{owner=1}
	e.board[1] = Tile{owner=2}
	e.board[2] = Tile{owner=3}
	e.board[3] = Tile{owner=4}
//odinfmt: enable
	///


	evacuate_tile(3, e)

	// checking
	{
		fmt.assertf(e.board[0].owner == 1, "Tile 0 was wrongfully touched")
		fmt.assertf(e.board[1].owner == 2, "Tile 1 was wrongfully touched")
		fmt.assertf(e.board[2].owner == 3, "Tile 2 was wrongfully touched")
		fmt.assertf(e.board[3].owner == 0, "Tile 3 wasn't rightfully touched")
	}
	fmt.println("test_test completed")
}

@(test)
test_no_prev_queue :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 1 * time.Second)

	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 4)
//odinfmt: disable
	e.board[0] = Tile{card=1}
	e.board[1] = Tile{card=2,owner=2}
	e.board[2] = Tile{card=3}
	e.board[3] = Tile{card=4}
//odinfmt: enable
	player_id: u64 : 1
	err: Game_err
	tile_pos :: 1
	player_id2 :: 2


	new_thread := thread.create_and_start_with_data(e, proc(_e: rawptr) {
		e := cast(^Effect)_e
		fmt.println("Just before sleeping")
		time.sleep(10 * time.Millisecond)
		if guard(&e.board_lock) {
			evacuate_tile(tile_pos, e)
		}
		fmt.println("tile evacuated")
	})

	///

	if guard(&e.board_lock) {
		///origial code
		err = handle_no_prev_choices(player_id, tile_pos, e)
		///
	}
	thread.join(new_thread)

	// checking
	{
		fmt.assertf(err == .Ok, "Should be ok")
		fmt.assertf(
			e.board[0] == Tile{card = 1},
			"Tile 0 should have the same card but no owner, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 2, owner = 1},
			"Tile 1 should be owned by 1, got %v instead",
			e.board[1],
		)
		fmt.assertf(
			e.board[2] == Tile{card = 3},
			"Tile 2 should have the same card but no owner, got %v instead",
			e.board[2],
		)
		fmt.assertf(
			e.board[3] == Tile{card = 4},
			"Tile 3 should have the same card but no owner, got %v instead",
			e.board[3],
		)

	}
	fmt.println("test_no_prev_queue completed")
}

//


@(test)
test_no_prev_b :: proc(t: ^testing.T) {

	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 4)
//odinfmt: disable
	e.board[0] = Tile{card=1}
	e.board[1] = Tile{card=2}
	e.board[2] = Tile{card=3}
	e.board[3] = Tile{card=4}
//odinfmt: enable
	player_id: u64 = 1
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = handle_no_prev_choices(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Ok, "Should be ok")
		fmt.assertf(
			e.board[0] == Tile{card = 1},
			"Tile 0 should have the same card but no owner, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 2, owner = 1},
			"Tile 1 should be owned by 1, got %v instead",
			e.board[1],
		)
		fmt.assertf(
			e.board[2] == Tile{card = 3},
			"Tile 2 should have the same card but no owner, got %v instead",
			e.board[2],
		)
		fmt.assertf(
			e.board[3] == Tile{card = 4},
			"Tile 3 should have the same card but no owner, got %v instead",
			e.board[3],
		)

	}
	fmt.println("test_no_prev_b completed")
}


@(test)
test_one_prev_2cde :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 2)
	
//odinfmt: disable
	e.board[0] = {card=1,owner=1}
	e.board[1] = {card=1,owner=0}
//odinfmt: enable

	player_id: u64 = 1
	player_poss := [2]int{1, 0}
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = handle_one_prev_choice(player_id, player_poss, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 1},
			"Tile 0 should have the same card but no owner, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 1, owner = 1},
			"Tile 1 should be owned by 1, got %v instead",
			e.board[1],
		)
	}
	fmt.println("test_one_prev_2cde completed")
}


@(test)
test_one_prev_2b :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 2)
	
//odinfmt: disable
	e.board[0] = {card=1,owner=1}
	e.board[1] = {card=1,owner=2}
//odinfmt: enable

	player_id: u64 = 1
	player_poss := [2]int{1, 0}
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = handle_one_prev_choice(player_id, player_poss, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 0},
			"Tile 0 should have the same card but no owner, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 1, owner = 2},
			"Tile 1 should be as it was, got %v instead",
			e.board[1],
		)
		fmt.assertf(true, "True is false")
	}
	fmt.println("test_one_prev_2b completed")
}


@(test)
test_one_prev_2a :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 2)
	
//odinfmt: disable
	e.board[0] = {card=1,owner=1}
	e.board[1] = {card=0}
//odinfmt: enable

	player_id: u64 = 1
	player_poss := [2]int{1, 0}
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = handle_one_prev_choice(player_id, player_poss, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 0},
			"Tile 0 should have the same card but no owner, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 0},
			"Tile 1 should remain completly empty, got %v instead",
			e.board[1],
		)
		fmt.assertf(true, "True is false")
	}
	fmt.println("test_one_prev_2a completed")
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

	e.board = make(#soa[]Tile, 3)
	player_id: u64 = 1
	///

	player_pos := find_player_pos(player_id, e)

	// checking
	{
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
	{
		fmt.assertf(
			player_pos == {1, 2},
			"Player positions should be {{0,1}}, %v instead",
			player_pos,
		)
	}
}

@(test)
test_2prev_diff :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 3)
	e.board[0] = {
		card  = 1,
		owner = 1,
	}
	e.board[1] = {
		card  = 2,
		owner = 1,
	}

	player_poss := [2]int{1, 2}
	player_id: u64 = 1
	err: Game_err = nil
	///

	///origial code
	err = handle_2prev_choices(player_poss, e)
	///

	// checking
	{
		fmt.assertf(
			err == .Conflict,
			"Status after flipping both should be .Conflict, got %v instead",
			err,
		)

		fmt.assertf(e.board[0].card == 1, "The first card should not be empty")
		fmt.assertf(e.board[1].card == 2, "The second card should not be empty")
		fmt.assertf(e.board[0].owner == 0, "The first card should not occupied")
		fmt.assertf(e.board[1].owner == 0, "The second card should not occupied")
	}
	fmt.println("test_2prev_diff completed")
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
	err: Game_err

	///


	err = handle_2prev_choices(player_poss, e)

	// checking
	{
		fmt.assertf(err == .Ok, "Status after removing both should be .Ok, got %v instead", err)

		fmt.assertf(e.board[0].card == NO_STRING, "The first card should be empty")
		fmt.assertf(e.board[1].card == NO_STRING, "The second card should be empty")
	}

	fmt.println("test_2prev_same completed")
}


// TODO:finish this
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
	err: Game_err
	player_name: string
	tile_pos: int
	///

	// write_guard: {
	// 	/// Original code
	// 	if tile.owner != NO_STRING {
	// 		place_back(&tile.wait_list, player_id)
	// 		// while tile is not evacuated to player_id or it still exists
	// 		for tile.owner != player_id && tile.card != NO_STRING {
	// 			sync.cond_wait(&tile.watch, &e.board_lock)
	// 		}
	// 		if tile.card != NO_STRING {
	// 			err = .Conflict
	// 		}
	// 		break write_guard
	// 	} else {
	// 		// there should be no situation where there is no owner but there is an waitlist
	// 		assert(tile.wait_list == 0)
	//
	// 		e.board[tile_pos].owner = player_id
	// 		log.debugf("%s choose free tile", player_name)
	//
	// 		board_was_updated(e)
	// 		break write_guard
	// 	}
	//
	// 	///
	// }

	// checking
	{
		fmt.assertf(true, "True is false")
	}
	fmt.println("test_rule_1bc completed")
}
