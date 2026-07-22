package main

import "core:math/rand"
import sdl "vendor:sdl2"

// ---- Constants ----

ENTRY_POINT_COUNT :: 15

ENTRY_POINTS := [ENTRY_POINT_COUNT]sdl.FPoint {
	// Top Edge
	{f32(SCREEN_WIDTH) * 0.1, -50},
	{f32(SCREEN_WIDTH) * 0.3, -50},
	{f32(SCREEN_WIDTH) * 0.5, -50},
	{f32(SCREEN_WIDTH) * 0.7, -50},
	{f32(SCREEN_WIDTH) * 0.9, -50},
	// Left Edge
	{-50, f32(SCREEN_HEIGHT) * 0.166},
	{-50, f32(SCREEN_HEIGHT) * 0.322},
	{-50, f32(SCREEN_HEIGHT) * 0.5},
	{-50, f32(SCREEN_HEIGHT) * 0.667},
	{-50, f32(SCREEN_HEIGHT) * 0.822},
	// Right Edge
	{SCREEN_WIDTH + 50, f32(SCREEN_HEIGHT) * 0.166},
	{SCREEN_WIDTH + 50, f32(SCREEN_HEIGHT) * 0.322},
	{SCREEN_WIDTH + 50, f32(SCREEN_HEIGHT) * 0.5},
	{SCREEN_WIDTH + 50, f32(SCREEN_HEIGHT) * 0.667},
	{SCREEN_WIDTH + 50, f32(SCREEN_HEIGHT) * 0.822},
}

// ---- Types ----


Wave :: struct {
	level, total_enemies, spawn_count, species_unlocked:                       int,
	threshold, spawn_delay, spawn_timer, dive_delay, dive_timer, speed_scalar: f32,
	path:                                                                      PathType,
	enemy_indices:                                                             [MAX_ENEMIES]int,
	is_active, formation_complete, threshold_crossed:                          bool,
	formation_complete_time:                                                   u64,
	control_points:                                                            [3]sdl.FPoint,
	formation_positions:                                                       [MAX_REGIONS][MAX_ENEMIES]sdl.FPoint,
	region_start:                                                              [MAX_REGIONS]sdl.FPoint,
	region_count:                                                              [MAX_REGIONS]int,
	spawn_region, spawn_index:                                                 int,
}

Level :: struct {
	wave:              [MAX_WAVES]Wave,
	wave_count, level: int,
	level_end:         bool,
	end_chance:        f32,
}

// ---- Init ----

wave_init :: proc(wp: ^WaveParams, wave: ^Wave) {
	region, count := compute_formation_bounds(wp)

	pool: [ENTRY_POINT_COUNT]int
	for i in 0 ..< ENTRY_POINT_COUNT do pool[i] = i
	entry_count := ENTRY_POINT_COUNT


	for i in 0 ..< count {
		base := BasicGenerationParams {
			bounds      = region[i],
			min_spacing = 5.0,
			count       = wp.total_enemies,
			positions   = &wave.formation_positions[i],
		}
		result := generate_formation(&base, wp.formation_params)

		r := rand.int_max(entry_count)
		chosen := pool[r]
		pool[r] = pool[entry_count - 1]
		entry_count -= 1

		wave.region_start[i] = ENTRY_POINTS[chosen]
		wave.region_count[i] = result.placed
	}
	wave.path = wp.path_type
	wave.speed_scalar = wp.speed_scalar
	wave.spawn_delay = wp.spawn_delay
	wave.is_active = true
}

level_init :: proc(bacteria: ^Bacteria, level: ^Level) {
	level_params := level_to_params(1)
	wave_init(&level_params, &level.wave[0])
}

// ---- Update ----
wave_update :: proc(wave: ^Wave, bacteria: ^Bacteria) {

}
