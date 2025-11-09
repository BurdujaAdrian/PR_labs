#+feature global-context
package main

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

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
//odinfmt: enable
	player_id: u64 : 1
	err: Game_err
	tile_pos := 0
	///


	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(true, "True is false")
	}
}


@(test)
test_1a :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 1)
//odinfmt: disable
	e.board[0] = Tile{}
//odinfmt: enable
	player_id: u64 : 1
	err: Game_err
	tile_pos := 0
	///

	/// original code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Conflict, "Should be conflict")
		fmt.assertf(e.board[0] == Tile{}, "Tile was not changed in any way")
	}
}

@(test)
test_1b :: proc(t: ^testing.T) {

	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 1)
//odinfmt: disable
	e.board[0] = Tile{card=1}
//odinfmt: enable
	player_id: u64 = 1
	err: Game_err
	tile_pos := 0
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Ok, "Should be ok")
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 1, flipped_by = 1},
			"card should be the same, except have flipped_by and owner = 1",
			e.board[0],
		)

	}
}

@(test)
test_1c :: proc(t: ^testing.T) {

	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 1)
//odinfmt: disable
	e.board[0] = Tile{card=1,flipped_by=124441}
//odinfmt: enable
	player_id: u64 = 1
	err: Game_err
	tile_pos := 0
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Ok, "Should be ok")
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 1, flipped_by = 1},
			"card should be the same, except have flipped_by and owner = 1",
			e.board[0],
		)

	}
}

@(test)
test_1d :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 1)
	
//odinfmt: disable
	e.board[0] = {card=1,owner=2,flipped_by=2}
//odinfmt: enable

	player_id: u64 = 1
	err: Game_err
	tile_pos := 0
	///

	td := thread.create_and_start_with_data(e, proc(data: rawptr) {
		e := cast(^Effect)data
		time.sleep(10 * time.Millisecond)
		_ = flip_tile(2, 0, e)
	})

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	thread.join(td)

	// checking
	{
		fmt.assertf(err == .Ok, "Should be ok, got %v", err)
		fmt.assertf(
			e.board[0].owner == e.board[0].flipped_by,
			"After wait, tile should be owned and flipped by 1, got %v instead",
			e.board[0],
		)
	}
}

@(test)
test_2a :: proc(t: ^testing.T) {
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
	e.board[0] = {card=1,owner=1,flipped_by=1}
	e.board[1] = {card=0}
//odinfmt: enable

	player_id: u64 = 1
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Conflict, "Should be conflict")

		fmt.assertf(
			e.board[0].owner == 0,
			"Tile 0 should have the same card, face up, but no owner, got %v instead",
			e.board[0],
		)
	}
}

@(test)
test_2b :: proc(t: ^testing.T) {
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
	e.board[0] = {card=1,owner=1,flipped_by=1}
	e.board[1] = {card=1,owner=2,flipped_by=2}
//odinfmt: enable

	player_id: u64 = 1
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Conflict, "Should be conflict, got %v", err)
		fmt.assertf(
			e.board[0].owner == 0,
			"Tile 0 should have the same card,face up but no owner, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 1, owner = 2, flipped_by = 2},
			"Tile 1 should be as it was, got %v instead",
			e.board[1],
		)
	}
}

@(test)
test_2cd :: proc(t: ^testing.T) {
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
	e.board[0] = {card=1,owner=1,flipped_by=1}
	e.board[1] = {card=1}
//odinfmt: enable

	player_id: u64 = 1
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Ok, "Should be ok")
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 1, flipped_by = 1},
			"Tile 0 should have the same card but owned and flipped by 1, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 1, owner = 1, flipped_by = 1},
			"Tile 0 should have the same card but owned and flipped by 1, got %v instead",
			e.board[1],
		)
	}
}

@(test)
test_2ce :: proc(t: ^testing.T) {
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
	e.board[0] = {card=1,owner=1,flipped_by=1}
	e.board[1] = {card=2}
//odinfmt: enable

	player_id: u64 = 1
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(err == .Conflict, "Should be conflict")
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 0, flipped_by = 1, watch = e.board[0].watch},
			"Tile 0 should have the same card but not owned and flipped by 1, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 2, owner = 0, flipped_by = 1, watch = e.board[1].watch},
			"Tile 0 should have the same card but not owned and flipped by 1, got %v instead",
			e.board[1],
		)
	}
}

@(test)
test_3a :: proc(t: ^testing.T) {
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
	e.board[0] = {card=1,owner=1,flipped_by=1}
	e.board[1] = {card=1}
//odinfmt: enable

	player_id: u64 = 1
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	err = flip_tile(player_id, tile_pos, e)
	///

	// checking
	{
		fmt.assertf(e.board[0].card == NO_STRING, "Tile 0 no string, got %v instead", e.board[0])
		fmt.assertf(e.board[1].card == NO_STRING, "Tile 1 no string, got %v instead", e.board[1])
	}
}
@(test)
test_3b :: proc(t: ^testing.T) {
	// memory
	test_arena: mem.Arena
	test_buff: [1024]u8 // slightly less,wont be needing allat
	mem.arena_init(&test_arena, test_buff[:])
	context.allocator = mem.arena_allocator(&test_arena)

	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board = make(#soa[]Tile, 3)
	
//odinfmt: disable
	e.board[0] = {card=1,owner=1,flipped_by=1}
	e.board[1] = {card=2}
	e.board[1] = {card=2}
//odinfmt: enable

	player_id: u64 = 1
	err: Game_err
	tile_pos := 1
	///

	///origial code
	err = flip_tile(player_id, tile_pos, e)
	err = flip_tile(player_id, 3, e)
	///

	// checking
	{
		fmt.assertf(
			e.board[0] == Tile{card = 1, owner = 0, flipped_by = 0, watch = e.board[0].watch},
			"Tile 0 should have the same card but not owned and flipped by 1, got %v instead",
			e.board[0],
		)
		fmt.assertf(
			e.board[1] == Tile{card = 2, owner = 0, flipped_by = 0, watch = e.board[0].watch},
			"Tile 0 should have the same card but not owned and flipped by 1, got %v instead",
			e.board[1],
		)
	}
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


	relinquish_tile(3, e)

	// checking
	{
		fmt.assertf(e.board[0].owner == 1, "Tile 0 was wrongfully touched")
		fmt.assertf(e.board[1].owner == 2, "Tile 1 was wrongfully touched")
		fmt.assertf(e.board[2].owner == 3, "Tile 2 was wrongfully touched")
		fmt.assertf(e.board[3].owner == 0, "Tile 3 wasn't rightfully touched")
	}
}


// @(test)
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

	player_pos, _ := find_player_pos(player_id, e)

	// checking
	{
		fmt.assertf(player_pos == 0, "Player positions should be {{0,0}}, %v instead", player_pos)
	}
}

// @(test)
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
	player_pos, _ := find_player_pos(player_id, e)
	///

	// checking
	{
		fmt.assertf(
			player_pos == {1, 2},
			"Player positions should be {{0,1}}, %v instead",
			player_pos,
		)
	}
}
