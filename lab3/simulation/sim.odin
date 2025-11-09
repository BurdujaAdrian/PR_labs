package sim

import super "../."
import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

main :: proc() {
	test_sim(nil)
}

thread_buf: [1024 * 4096]u8

@(test)
test_sim :: proc(t: ^testing.T) {
	using super
	thread_arena: mem.Arena
	mem.arena_init(&thread_arena, thread_buf[:])
	context.allocator = mem.arena_allocator(&thread_arena)


	time.sleep(1 * time.Second)
	/// Initial conditions
	_e := Effect{}
	e := &_e

	e.board_w, e.board_h, e.hash_map, e.board = parse_board("testboard.txt")
	defer {free(&e.hash_map)}
	assert(len(e.board) == 18)

	threads := make([dynamic]^thread.Thread)

	for _ in 0 ..< 4 {
		thred := thread.create_and_start_with_data(
		e,
		proc(data: rawptr) {

			e := cast(^Effect)data
			//


			assert(len(e.board) == 18)
			player_id := u64(os.current_thread_id())

			fmt.println(
				"===================================================",
				"||>",
				os.current_thread_id(),
				"started succesfully",
				"===================================================",
			)
			i: u128 = 0
			loop: for {
				thread_buf: [4096]u8
				thread_arena: mem.Arena
				mem.arena_init(&thread_arena, thread_buf[:])
				context.allocator = mem.arena_allocator(&thread_arena)

				rand.reset(player_id * auto_cast i)
				tile_pos := rand.int_max(len(e.board))
				assert(tile_pos >= 0)


				err := flip_tile(player_id, tile_pos, e)

				// if err != nil {
				// 	fmt.printfln("\tflip of %v by %v was succesfull", tile_pos, player_id)
				// } else {
				// 	fmt.printfln("\tflip of %v by %v was not succesfull", tile_pos, player_id)
				// }

				// fmt.println("\t", strings.replace_all(look(player_id, e), "\n", "|"))
				// fmt.printfln("<<<<<<< %v", player_id)

				if board_is_empty(e) {
					break loop
				}
				i += 1
			}

			fmt.println(
				"===================================================",
				"<||",
				os.current_thread_id(),
				"ended succesfully after",
				i,
				"iterations",
				"===================================================",
			)

		},
		)

		if thred != nil do append(&threads, thred)
		fmt.println("Thred added")
	}


	for thred in threads {
		thread.join(thred)
	}
	log.info(#procedure, "finished succesfully")
}
