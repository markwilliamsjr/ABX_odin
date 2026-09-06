package main

import "core:container/pool"
import "core:fmt"
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
	level, total_enemies, spawn_count, species_unlocked, max_simult_divers:    int,
	threshold, spawn_delay, spawn_timer, dive_delay, dive_timer, speed_scalar: f32,
	path:                                                                      PathType,
	enemy_indices:                                                             [MAX_ENEMIES]int,
	is_active, formation_complete, threshold_crossed:                          bool,
	formation_complete_time:                                                   u64,
	control_points:                                                            [3]sdl.FPoint,
	formation_positions:                                                       [MAX_REGIONS][MAX_ENEMIES]sdl.FPoint,
	region_start:                                                              [MAX_REGIONS]sdl.FPoint,
	region_enemy_count:                                                        [MAX_REGIONS]int,
	spawn_region, spawn_index:                                                 int,
	diver_selection_rule:                                                      DiverSelectionRule,
}

Level :: struct {
	wave:              [MAX_WAVES]Wave,
	wave_count, level: int,
	level_end:         bool,
	end_chance:        f32,
}

// ---- Init ----

wave_init :: proc(wp: ^WaveParams, wave: ^Wave, wave_seed: u64) {
	fmt.println("Wave Seed: ", wave_seed)

	entry_rng_state := rand.create(derive_seed(wave_seed, .Entry, 0))
	entry_rng := &entry_rng_state

	region_size, region_count := compute_formation_bounds(wp)

	entry_rules := EntryRules {
		available_points = ENTRY_POINTS[:],
		count            = region_count,
	}

	entry_point_result, entry_ok := generate_entry_points(entry_rng, entry_rules)

	if !entry_ok {
		// TODO need fall back
	}
	base := BasicGenerationParams {
		bounds      = region_size[0],
		min_spacing = 5.0,
		count       = wp.total_enemies,
		positions   = &wave.formation_positions[0],
	}
	result := generate_formation(&base, wp.formation_params)

	for i in 0 ..< region_count {
		wave.region_start[i] = entry_point_result.start_points[i]
		wave.region_enemy_count[i] = result.placed
	}

	wave.path = wp.path_type
	wave.speed_scalar = wp.speed_scalar
	wave.spawn_delay = wp.spawn_delay
	wave.is_active = true
	wave.total_enemies = wp.total_enemies
	wave.max_simult_divers = wp.max_simult_divers
	wave.diver_selection_rule = wp.diver_selection_rule
	wave.formation_complete = false
}

level_init :: proc(bacteria: ^Bacteria, level: ^Level, seed: u64) {
	wave_seed := derive_seed(seed, .Wave, 0)
	level_params := level_to_params(1)
	wave_init(&level_params, &level.wave[0], wave_seed)
}

// ---- Update ----
wave_update :: proc(wave: ^Wave, bacteria: ^Bacteria, delta_time: f32) {
	if wave.spawn_count < wave.total_enemies {
		wave.spawn_timer += delta_time
		if wave.spawn_delay > wave.spawn_timer do return

		wave.spawn_timer -= wave.spawn_delay

		for wave.spawn_index >= wave.region_enemy_count[wave.spawn_region] {
			wave.spawn_region += 1
			wave.spawn_index = 0
		}

		start := wave.region_start[wave.spawn_region]
		destination := wave.formation_positions[wave.spawn_region][wave.spawn_index]
		path_data := generate_entry_path(wave.path, start, destination)

		params := BacteriaSpawnParams {
			speed_scalar       = wave.speed_scalar,
			path_data          = path_data,
			formation_position = destination,
			species            = .Strep,
		}
		wave.enemy_indices[wave.spawn_count] = bacteria_spawn(bacteria, &params)
		wave.spawn_index += 1
		wave.spawn_count += 1
	}

	// Check if holding
	if wave.spawn_count == wave.total_enemies && !wave.formation_complete {
		all_holding := true
		for i in 0 ..< wave.spawn_count {
			if bacteria.cold[wave.enemy_indices[i]].bacteria_state != .Holding {
				all_holding = false
				break
			}
		}
		if all_holding {
			wave.formation_complete = true
			wave.formation_complete_time = u64(sdl.GetTicks())
		}
	}
}

wave_dive_update :: proc(wave: ^Wave, bacteria: ^Bacteria, delta_time: f32) {
	if !wave.formation_complete do return

	wave.dive_timer += delta_time
	if wave.dive_delay > wave.dive_timer do return

	if u64(sdl.GetTicks()) >= wave.formation_complete_time {
		divers_count := 0
		for i in 0 ..< wave.spawn_count {
			idx := wave.enemy_indices[i]
			if bacteria.cold[idx].bacteria_state == .Diving {
				divers_count += 1
			}
		}
		if divers_count >= wave.max_simult_divers {
			return
		}
		idx := select_diver(wave, bacteria)
		if idx != -1 {
			bacteria.cold[idx].bacteria_state = .Diving
		}
	}
}

// ---- Helper ----

generate_entry_points :: proc(
	rng: ^rand.Default_Random_State,
	rules: EntryRules,
) -> (
	result: EntryResult,
	ok: bool,
) {
	if rules.count < len(rules.available_points) {
		return {}, false
	}
	pool := make([]int, len(rules.available_points), context.temp_allocator)
	for i in 0 ..< len(pool) do pool[i] = i
	remaining := len(pool)

	for i in 0 ..< rules.count {
		r := rand.int_max(remaining)
		chosen := pool[r]
		pool[r] = pool[remaining - 1]
		remaining -= 1

		result.start_points[i] = rules.available_points[chosen]
	}
	result.count = rules.count
	return result, true
}
