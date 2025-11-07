# Lab3

## Elaborated by: Burduja Adrian faf231

## Task
For this lab you will implement the MIT 6.102 (2025) Memory Scramble lab.
You can find the starter code that they provide to the students in this Github repo.
You are free to use any HTTP and unit test libraries.

## Structure

### The board

I choose to represent the board as an array of tiles, where a tile is described as:
```odin
Tile :: struct {
	card:      u64,
	owner:     u64,
	watch:     sync.Cond,
	wait_list: [MAX_PLAYERS]u64,
}
```

The state of a single tile is defined by the card it houses, the player who owns it,
a list of playier waiting to aquire the tile and a condition variable that takes care
to notify waiting players when the the tile is freed or removed.

The card and owner would normally be a string, however because of memory and performance
reasons I opted for a hash of those strings instead.

A removed tile(as happens when 2 of the same are revealed by 1 player) are signified by
having card = 0. A tile not owned by anyone is represented the same way.

The state of the tile being face-up or face-down is dependant on whether it has an owner
or not.

This is showcased in the look function which reads the table and formats the response 
based on the state:
```odin
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
```

To make mutations of the board simpler, the most oftenly used operations are factored
out into separate functions:
```odin
POS_INT_MAX: int : 1 << 63 - 1
//@game helpers
find_player_pos :: proc(player_id: u64, e: ^Effect) -> (res: [2]int) {
	fmt.assertf(len(e.board) < POS_INT_MAX, "Board size: %v >= MAX: %v", len(e.board), POS_INT_MAX)
	for id, i in e.board.owner[:len(e.board)] {
		if player_id == id {
			switch {
			case res[0] == 0: res[0] = i + 1
			case res[1] == 0: res[1] = i + 1
			case: assert(res[0] != 0 && res[1] != 0)
				fmt.assertf(false, "Any player should not have more than 2 cards owned at a time")
			}
		}
	}
	return
}
```

There is no state tracking for the previous choices of the players, instead I opted
to linearly search the board for the index of the tiles said player has flipped before.
This algorithm might look inefficient, however because the array is not an array of
structures but a structure of arrays: meaning each field is it's own attay, arranged
in the continuous memory. This factor coupled with the assumption, that on averege
this array would be relatively small makes this implementation exeedingly efficient.

One invarient that this finction checks is that the player must not hold more then 2
tiles. If this case is hit, the program is incorrect and in an invalid state and must 
terminate.

Another invarient is that the size of the board is smaller then the biggest positive
integer. This exists to ensure no integer overflow happens on the addition operation.

```odin
evacuate_tile :: proc(pos: int, e: ^Effect) {
	fmt.assertf(pos > -1, "input pos must be positive")
	e.board[pos].owner = pop_front(&e.board[pos].wait_list)
	sync.cond_broadcast(&e.board[pos].watch)
}
```

`evacuate_tile` has the jobs of freeing the tile at `pos`, putting the first player_id
in from the waitlist as the owner, and notifying the threads that are waiting on this 
tile.

Since pos has to index an array, it must be a positive integer, which is checked by the
assert 

```odin
board_was_updated :: #force_inline proc(e: ^Effect) {
	if guard(&e.update_lock) {
		e.was_updated = true
		sync.cond_broadcast(&e.update_watch)
	}
}
```

This procedure simply broadcasts that the board was updated to the watch function.


## Screenshots
![Race condition commands](./run_bad.png)

## Implementation



## Conclusion
This laboratory successfully enhanced the HTTP server with multithreading, thread-safe
counters, and rate limiting. The implementation used a ThreadPoolExecutor to handle 
concurrent connections, achieving significant performance improvements over the 
single-threaded version. A custom read-write lock was developed to resolve race 
conditions in the access counter, ensuring data consistency while maintaining 
performance. Rate limiting was implemented using a dual-map swapping mechanism to 
efficiently track client requests while preventing memory leaks. The project 
demonstrated practical understanding of concurrent programming challenges and their 
solutions, including proper synchronization techniques and resource management in 
multi-threaded environments.


