package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl2"

// ---- Constants ----

ENTRY_POINT_COUNT :: 15
FLEE_THRESHOLD_PER_BUFF :: 50

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
	level, enemy_count, spawn_count, species_unlocked, max_simult_divers:     int,
	threshold_permille:                                                       int,
	spawn_delay_ticks, spawn_timer, dive_delay_ticks, dive_timer:             int,
	speed_scalar:                                                             f32,
	path:                                                                     PathType,
	formation_complete, threshold_crossed, spawn_finished, flee_phase_active: bool,
	flee_start_tick, formation_complete_tick, seed:                           u64,
	control_points:                                                           [3]sdl.FPoint,
	formation_positions:                                                      [MAX_REGIONS][MAX_ENEMIES]sdl.FPoint,
	region_start:                                                             [MAX_REGIONS]sdl.FPoint,
	region_enemy_count:                                                       [MAX_REGIONS]int,
	spawn_region, spawn_index:                                                int,
	diver_selection_rule:                                                     DiverSelectionRule,
	destroyed_count, fled_count, index, region_count:                         int,
}

Level :: struct {
	wave:                                 [MAX_WAVES]Wave,
	bacteria:                             Bacteria,
	wave_count, level_number, wave_index: int,
	level_end, flee_prohibited:           bool,
}

// ---- Init ----

wave_init :: proc(
	wp: ^WaveParams,
	wave: ^Wave,
	wave_seed: u64,
	enemy_count, level: int,
	wave_index: int,
	flee_prohibited: bool,
) {
	wave.index = wave_index
	wave.level = level
	wave.seed = wave_seed
	wave.spawn_count = 0
	wave.spawn_index = 0
	wave.spawn_timer = 0
	wave.dive_timer = 0
	wave.flee_start_tick = 0
	wave.formation_complete_tick = 0
	wave.destroyed_count = 0
	wave.fled_count = 0
	wave.spawn_region = 0
	wave.species_unlocked = wp.species_unlocked

	wave.threshold_crossed = false
	wave.formation_complete = false
	wave.spawn_finished = false
	wave.flee_phase_active = false

	entry_rng_state := rand.create(derive_seed(wave_seed, .Entry, 0))
	entry_rng := runtime.default_random_generator(&entry_rng_state)

	if flee_prohibited {
		wave.threshold_permille = 1000
		fmt.printfln("[wave %v] flee prohibited", wave.index)
	} else {
		threshold_rng_state := rand.create(derive_seed(wave_seed, .Level, 0))
		threshold_rng := runtime.default_random_generator(&threshold_rng_state)
		wave.threshold_permille = threshold_picker(level, threshold_rng)
	}

	region_size, region_count := compute_formation_bounds(wp)
	wave.region_count = region_count

	entry_rules: EntryRules

	if level <= 2 {
		entry_rules = EntryRules {
			available_points = ENTRY_POINTS[2:3],
			count            = region_count,
		}
	} else {
		entry_rules = EntryRules {
			available_points = ENTRY_POINTS[:],
			count            = region_count,
		}
	}

	entry_point_result, entry_ok := generate_entry_points(entry_rng, entry_rules)
	if !entry_ok {
		// TODO added fall back
	}

	base := BasicGenerationParams {
		bounds      = region_size[0],
		min_spacing = 5.0,
		count       = enemy_count,
		positions   = &wave.formation_positions[0],
	}
	result := generate_formation(&base, wp.formation_params)

	for i in 0 ..< region_count {
		wave.region_start[i] = entry_point_result.start_points[i]
		wave.region_enemy_count[i] = result.placed
	}

	wave.path = wp.path_type
	wave.speed_scalar = wp.speed_scalar
	wave.spawn_delay_ticks = int(f32(wp.spawn_delay) * f32(TICK_RATE) + 0.5)
	wave.dive_delay_ticks = int(f32(wp.dive_delay) * f32(TICK_RATE) + 0.5)
	wave.enemy_count = enemy_count
	wave.max_simult_divers = wp.max_simult_divers
	wave.diver_selection_rule = wp.diver_selection_rule
}

level_init :: proc(level: ^Level, master_seed: u64, level_number: int) {
	bacteria_pool_reset(&level.bacteria)
	level.level_number = level_number
	level_seed := derive_seed(master_seed, .Level, level.level_number)
	level_params := level_to_params(level.level_number)
	wave_rng_state := rand.create(derive_seed(level_seed, .Level, 0))
	wave_rng := runtime.default_random_generator(&wave_rng_state)
	level.wave_count = wave_count_picker(level.level_number, wave_rng)
	level.wave_index = 0
	level.level_end = false
	level.flee_prohibited = false

	base := level_params.enemy_budget / level.wave_count
	extra := level_params.enemy_budget % level.wave_count
	block_number := (level.level_number - 1) / 5

	level.wave = {}

	for i in 0 ..< level.wave_count {
		share := base + (1 if i < extra else 0)
		share = max(share, WAVE_ENEMY_FLOOR)

		band: int
		if block_number == 0 {
			band = 0
		} else {
			band = 1
		}

		wave_seed := derive_seed(level_seed, .Wave, i)

		jitter_rng_state := rand.create(derive_seed(wave_seed, .Wave, 0))
		jitter_rng := runtime.default_random_generator(&jitter_rng_state)
		jitter: int
		if band == 0 {
			jitter = 0
		} else {
			jitter = rand.int_range(-band, band + 1, jitter_rng)
		}

		share = clamp(share + jitter, WAVE_ENEMY_FLOOR, MAX_ENEMIES)

		wave_init(
			&level_params,
			&level.wave[i],
			wave_seed,
			share,
			level_number,
			i,
			level.flee_prohibited,
		)
	}

}

// ---- Update ----
wave_update :: proc(
	wave: ^Wave,
	bacteria: ^Bacteria,
	roster: ^ReturnRoster,
	ticks_this_frame: int,
	total_tick: u64,
) {
	if !wave.spawn_finished {
		wave.spawn_timer += ticks_this_frame
		if wave.spawn_delay_ticks > wave.spawn_timer do return

		wave.spawn_timer -= wave.spawn_delay_ticks

		for wave.spawn_region < wave.region_count &&
		    wave.spawn_index >= wave.region_enemy_count[wave.spawn_region] {
			wave.spawn_region += 1
			wave.spawn_index = 0
		}
		if wave.spawn_region == wave.region_count {
			wave.spawn_finished = true
			fmt.printfln(
				"[wave %v] spawn shortfall: %v/%v spawned, %v region(s) exhausted",
				wave.index,
				wave.spawn_count,
				wave.enemy_count,
				wave.region_count,
			)
		} else {
			start := wave.region_start[wave.spawn_region]
			destination := wave.formation_positions[wave.spawn_region][wave.spawn_index]
			path_data := generate_entry_path(wave.path, start, destination)

			due := return_roster_front_due(roster)
			species: BacteriaSpecies = .Strep
			buff: [MAX_BUFFS]BuffInstance
			buff_count := 0
			if due {
				entry := roster.entries[0]
				species = entry.species
				buff = entry.buffs
				buff_count = entry.buff_count
			} else {
				rng_state := rand.create(derive_seed(wave.seed, .Wave, 1 + wave.spawn_index))
				rng := runtime.default_random_generator(&rng_state)
				count := min(wave.species_unlocked, len(BACTERIA_DEFS))
				species = BacteriaSpecies(rand.int_range(0, count, rng))
			}

			params := BacteriaSpawnParams {
				speed_scalar       = wave.speed_scalar,
				path_data          = path_data,
				formation_position = destination,
				wave_index         = wave.index,
				species            = species,
				buffs              = buff,
				buff_count         = buff_count,
			}
			idx := bacteria_spawn(bacteria, &params)
			if idx == -1 {
				return
			}
			if due {
				_, _ = return_roster_pop(roster)
				fmt.printfln(
					"[wave %v] return: slot=%v species=%v buffs=%v",
					wave.index,
					idx,
					species,
					buff_count,
				)
			}
			wave.spawn_index += 1
			wave.spawn_count += 1
			if wave.spawn_count == wave.enemy_count {
				wave.spawn_finished = true
			}
		}
	}
	if !wave.threshold_crossed && wave.spawn_finished && wave.spawn_count > 0 {
		effective := wave_effective_threshold(wave, bacteria)
		if wave.destroyed_count * 1000 >= wave.spawn_count * effective {
			wave.threshold_crossed = true
			fmt.printfln(
				"[wave %v] threshold crossed: destroyed = %v/%v; permille = %v",
				wave.index,
				wave.destroyed_count,
				wave.spawn_count,
				wave.threshold_permille,
			)
			wave_flee_begin(wave, bacteria, wave.level, total_tick)
		}
	}

	// Check if holding
	if wave.spawn_finished && !wave.formation_complete {
		all_holding := true
		owned := 0
		for i in 0 ..< MAX_ENEMIES {
			if !bacteria.hot[i].active do continue
			if bacteria.cold[i].wave_index != wave.index do continue
			owned += 1
			if bacteria.cold[i].bacteria_state != .Holding {
				all_holding = false
				break
			}
		}
		if all_holding && owned == wave.spawn_count {
			wave.formation_complete = true
			wave.formation_complete_tick = total_tick
		}
	}
}

wave_flee_begin :: proc(wave: ^Wave, bacteria: ^Bacteria, level: int, total_tick: u64) {
	fleeing := 0
	for i in 0 ..< MAX_ENEMIES {
		if !bacteria.hot[i].active do continue
		if bacteria.cold[i].wave_index != wave.index do continue
		buff_rng_state := rand.create(derive_seed(wave.seed, .Buff, i))
		buff_rng := runtime.default_random_generator(&buff_rng_state)
		category := BuffCategory(rand.int_range(0, len(BUFF_DEFS), buff_rng))
		fraction := buff_fraction_permille(level, buff_rng)
		bacteria_buff_add(&bacteria.cold[i], {category, fraction})
		fmt.printfln(
			"[wave %v] flee: slot=%v cat=%v fraction=%v count=%v",
			wave.index,
			i,
			category,
			fraction,
			bacteria.cold[i].buff_count,
		)
		bacteria.cold[i].bacteria_state = .Fleeing
		fleeing += 1
		wave.flee_phase_active = true
	}
	if wave.flee_phase_active {
		wave.flee_start_tick = total_tick
		fmt.printfln("[wave %v] flee begin: fleeing=%v", wave.index, fleeing)
	}
}

wave_flee_update :: proc(
	wave: ^Wave,
	bacteria: ^Bacteria,
	roster: ^ReturnRoster,
	total_tick: u64,
) {
	if !wave.flee_phase_active do return
	wave_flee_finish(wave, bacteria, roster, total_tick)
}

wave_flee_finish :: proc(
	wave: ^Wave,
	bacteria: ^Bacteria,
	roster: ^ReturnRoster,
	total_tick: u64,
) {
	for i in 0 ..< MAX_ENEMIES {
		if !bacteria.hot[i].active do continue
		if bacteria.cold[i].wave_index != wave.index do continue
		entry := PendingBacteria {
			species            = bacteria.hot[i].species,
			buffs              = bacteria.cold[i].buffs,
			buff_count         = bacteria.cold[i].buff_count,
			waves_until_return = 1,
		}
		return_roster_push(roster, entry)
		fmt.printfln(
			"[roster] push: species=%v buffs=%v delay=%v roster=%v",
			entry.species,
			entry.buff_count,
			entry.waves_until_return,
			roster.count,
		)
		bacteria.hot[i].active = false
		bacteria.cold[i].wave_index = OWNER_NONE
		wave.fled_count += 1
	}
	wave.flee_phase_active = false
	elapsed_ticks := total_tick - wave.flee_start_tick
	fmt.printfln(
		"[wave %v] flee finish: fled=%v; roster=%v; elapsed=%vms",
		wave.index,
		wave.fled_count,
		roster.count,
		(elapsed_ticks * 1000) / u64(TICK_RATE),
	)
}

wave_dive_update :: proc(wave: ^Wave, bacteria: ^Bacteria, ticks_this_frame: int) {
	if !wave.formation_complete do return

	wave.dive_timer += ticks_this_frame
	if wave.dive_delay_ticks > wave.dive_timer do return


	if u64(sdl.GetTicks()) >= wave.formation_complete_tick {
		divers_count := 0
		for i in 0 ..< MAX_ENEMIES {
			if !bacteria.hot[i].active do continue
			if bacteria.cold[i].wave_index != wave.index do continue
			if bacteria.cold[i].bacteria_state == .Diving {
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

wave_resolution_update :: proc(level: ^Level) -> bool {
	if level.wave[level.wave_index].spawn_finished &&
	   level.wave[level.wave_index].spawn_count > 0 &&
	   wave_resolved(&level.wave[level.wave_index]) == level.wave[level.wave_index].spawn_count &&
	   !level.wave[level.wave_index].flee_phase_active {
		fmt.printfln(
			"[wave %v] resolved: destroyed=%v/%v; fled=%v",
			level.wave_index,
			level.wave[level.wave_index].destroyed_count,
			level.wave[level.wave_index].spawn_count,
			level.wave[level.wave_index].fled_count,
		)
		done := level.wave_index
		level.wave_index += 1
		fmt.printfln(
			"[wave %v] advance: next=%v; wave_count=%v",
			done,
			level.wave_index,
			level.wave_count,
		)
		if level.wave_index == level.wave_count {
			level.level_end = true
			fmt.printfln("[level %v] end: waves=%v", level.level_number, level.wave_count)
		}
		return true
	}
	return false
}

// ---- Helper ----

generate_entry_points :: proc(
	rng: runtime.Random_Generator,
	rules: EntryRules,
) -> (
	result: EntryResult,
	ok: bool,
) {
	if rules.count > len(rules.available_points) {
		return {}, false
	}
	pool := make([]int, len(rules.available_points), context.temp_allocator)
	for i in 0 ..< len(pool) do pool[i] = i
	remaining := len(pool)

	for i in 0 ..< rules.count {
		r := rand.int_max(remaining, rng)
		chosen := pool[r]
		pool[r] = pool[remaining - 1]
		remaining -= 1

		result.start_points[i] = rules.available_points[chosen]
	}
	result.count = rules.count
	return result, true
}

wave_count_picker :: proc(level: int, wave_rng: runtime.Random_Generator) -> int {
	block_number := (level - 1) / 5
	if block_number == 0 {
		if 1 == min(level, 4) {
			return 1
		}
		return rand.int_range(1, min(level, 4) + 1, wave_rng)
	}
	min := 1 + block_number * 2
	max := min + 3
	if min > MAX_WAVES {
		return MAX_WAVES
	}
	if max >= MAX_WAVES {
		return rand.int_range(min, MAX_WAVES + 1, wave_rng)
	}
	return rand.int_range(min, max + 1, wave_rng)
}

threshold_picker :: proc(level: int, wave_rng: runtime.Random_Generator) -> int {
	t := clamp(f32(level - 1) / 20, 0, 1)
	base := 500 + 225 * (1 + math.cos(math.PI * t))
	spread := f32(rand.int_range(-50, 51, wave_rng))
	return int(clamp(base + spread, 500, 1000))
}

wave_resolved :: proc(wave: ^Wave) -> int {
	return wave.destroyed_count + wave.fled_count
}

wave_max_buff_count :: proc(wave: ^Wave, bacteria: ^Bacteria) -> int {
	max_buffs := 0
	for i in 0 ..< MAX_ENEMIES {
		if !bacteria.hot[i].active do continue
		if bacteria.cold[i].wave_index != wave.index do continue
		if bacteria.cold[i].buff_count > max_buffs {
			max_buffs = bacteria.cold[i].buff_count
		}
	}
	return max_buffs
}

wave_effective_threshold :: proc(wave: ^Wave, bacteria: ^Bacteria) -> int {
	return clamp(
		wave.threshold_permille + FLEE_THRESHOLD_PER_BUFF * wave_max_buff_count(wave, bacteria),
		500,
		1000,
	)
}
