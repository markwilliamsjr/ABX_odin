package main

import sdl "vendor:sdl2"

// ---- Types ----

Wave :: struct {
	level, total_enemies, spawn_count, species_unlocked: int,
	threshold, spawn_delay, spawn_timer, dive_delay, dive_timer, speed_scalar: f32,
	path: PathType,
	enemy_indices: [MAX_ENEMIES]int,
	is_active, formation_complete, threshold_crossed: bool,
	formation_complete_time: u64,

	control_points: [3]sdl.FPoint
	formation_positions: [MAX_ENEMIES]sdl.FPoint
}

Level :: struct {
	wave:              [MAX_WAVES]Wave,
	wave_count, level: int,
	level_end: bool,
	end_chance: f32,
}

Wave :: struct {}
