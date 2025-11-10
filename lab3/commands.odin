package main

flip :: proc(player_id: u64, tile_pos: int, e: ^Effect) -> (boardstate: string, err: Game_err) {
	err = flip_tile(player_id, tile_pos, e)
	return board_look(player_id, e), err
}


replace :: proc(to, from: string, player_id: u64, e: ^Effect) -> (string, Game_err) {
	return board_look(player_id, e), board_map(to, from, e)
}

watch :: proc(player_id: u64, e: ^Effect) -> string {
	board_watch(e)
	return board_look(player_id, e)
}

look :: proc(player_id: u64, e: ^Effect, loc := #caller_location) -> string {
	return board_look(player_id, e)
}
