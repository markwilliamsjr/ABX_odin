package main

import "core:math/rand"
import sdl "vendor:sdl2"

// ---- Types ----

Wave :: struct {
	level, total_enemies, spawn_count, species_unlocked:                       int,
	threshold, spawn_delay, spawn_timer, dive_delay, dive_timer, speed_scalar: f32,
	path:                                                                      PathType,
	enemy_indices:                                                             [MAX_ENEMIES]int,
	is_active, formation_complete, threshold_crossed:                          bool,
	formation_complete_time:                                                   u64,
	control_points:                                                            [3]sdl.FPoint,
	formation_positions:                                                       [MAX_ENEMIES]sdl.FPoint,
}

Level :: struct {
	wave:              [MAX_WAVES]Wave,
	wave_count, level: int,
	level_end:         bool,
	end_chance:        f32,
}

// ---- Init ----

wave_init :: proc(wp: ^WaveParams, bacteria: ^Bacteria, wave: ^Wave) {
	region, count := compute_formation_bounds(wp)
	placed_total := 0

	for i in 0 ..< count {
		base := BasicGenerationParams {
			bounds      = region[i],
			min_spacing = 5.0,
			count       = wp.total_enemies,
			positions   = wave.formation_positions[placed_total:],
		}
		result := generate_formation(base, wp.formation_params)

		for j in 0 ..< result.placed {
			start := sdl.FPoint {
				x = rand.float32() * f32(SCREEN_WIDTH),
				y = -50,
			}
			bact_spawn_params := BacteriaSpawnParams {
				speed_scalar        = wp.speed_scalar,
				path_data           = generate_entry_path(
					wp.path_type,
					start,
					wave.formation_positions[placed_total + j],
				),
				formation_posistion = wave.formation_positions[placed_total + j],
				species             = .Strep,
			}
			wave.enemy_indices = bacteria_spawn(bacteria, &bact_spawn_params)
		}
		placed_total += result.placed
	}
}

level_init :: proc(bacteria: ^Bacteria, level: ^Level) {
	level_params := level_to_params(1)
	wave_init(&level_params, bacteria, &level.wave[0])
}
