package main

import "core:math"
import "core:math/rand"
import sdl "vendor:sdl2"
// ---- Constants ----

// ---- Types ----
BacteriaSpecies :: enum {
	Strep,
	Staph,
	Ecoli,
	Pseudomonas,
}

Scatter_Phase :: enum {
	Bursting,
	Pausing,
	Diving,
}

Zigzag_Phase :: enum {
	Dashing,
	Pausing,
}

Sine_Dive :: struct {
	phase:      f32,
	amplitude:  f32,
	frequency:  f32,
	start_x:    f32,
	dive_speed: f32,
}

Scatter_Dive :: struct {
	burst_angle:    f32,
	burst_speed:    f32,
	burst_pause:    f32,
	burst_duration: f32,
	timer:          f32,
	start_x:        f32,
	start_y:        f32,
	target_x:       f32,
	phase:          Scatter_Phase,
}

Zigzag_Dive :: struct {
	direction: int,
	cooldown:  f32,
	timer:     f32,
	speed:     f32,
	start_x:   f32,
	start_y:   f32,
	phase:     Zigzag_Phase,
}

Sweep_Dive :: struct {
	control_points: [4]sdl.FPoint,
	t:              f32,
}

DiveType :: union {
	Sine_Dive,
	Scatter_Dive,
	Zigzag_Dive,
	Sweep_Dive,
}

Bacteria :: struct {
	hot:  [MAX_ENEMIES]BacteriaHot,
	cold: [MAX_ENEMIES]BacteriaCold,
}

BacteriaSpawnParams :: struct {
	speed_scalar:       f32,
	path_data:          EntryPathData,
	formation_position: sdl.FPoint,
	species:            BacteriaSpecies,
}

BacteriaDefinition :: struct {
	species:             BacteriaSpecies,
	weakness:            WeaponType,
	r, g, b:             u8,
	health, base_speed:  int,
	width, height:       int,
	hb_width, hb_height: int,
	offset_x, offset_y:  int,
	frame_count:         int,
	frame_duration:      f32,
	texture_path:        string,
}

BacteriaState :: enum {
	Entering,
	Holding,
	Diving,
	Returning,
	Fleeing,
}

BacteriaHot :: struct {
	x, y, animation_timer, angle:              f32,
	width, height, hb_width, hb_height:        int,
	offset_x, offset_y, health, current_frame: int,
	active:                                    bool,
	species:                                   BacteriaSpecies,
}

BacteriaCold :: struct {
	bacteria_state:                                    BacteriaState,
	entry_path:                                        EntryPathData,
	dive_type:                                         DiveType,
	current_segment:                                   int,
	pause_timer:                                       f32,
	state_start_time:                                  u64,
	t, speed, speed_scalar:                            f32,
	dive_initialized, return_initialized, should_flee: bool,
	formation_point, return_start_point:               sdl.FPoint,
}

// ---- Definitions / Table ----

BACTERIA_DEFS := [BacteriaSpecies]BacteriaDefinition {
	.Strep = {
		species = .Strep,
		weakness = .PCN,
		r = 0,
		g = 200,
		b = 0,
		health = 6,
		base_speed = 400.0,
		width = 32,
		height = 64,
		hb_width = 22,
		hb_height = 64,
		offset_x = 5,
		offset_y = 0,
		frame_count = 12,
		frame_duration = 1.0 / 12.0,
		texture_path = "assets/bacteria/strep.png",
	},
	.Staph = {
		species = .Staph,
		weakness = .PCN,
		r = 150,
		g = 200,
		b = 0,
		health = 6,
		base_speed = 300.0,
		width = 50,
		height = 50,
		hb_width = 50,
		hb_height = 50,
		offset_x = 0,
		offset_y = 0,
		frame_count = 1,
		frame_duration = 0.0,
		texture_path = "assets/bacteria/staph.png",
	},
	.Ecoli = {
		species = .Ecoli,
		weakness = .PMX,
		r = 0,
		g = 100,
		b = 200,
		health = 6,
		base_speed = 300.0,
		width = 50,
		height = 50,
		hb_height = 50,
		hb_width = 50,
		offset_x = 0,
		offset_y = 0,
		frame_count = 1,
		frame_duration = 0.0,
		texture_path = "assets/bacteria/ecoli.png",
	},
	.Pseudomonas = {
		species = .Pseudomonas,
		weakness = .PMX,
		r = 0,
		g = 200,
		b = 200,
		health = 6,
		base_speed = 400.0,
		width = 50,
		height = 50,
		hb_width = 50,
		hb_height = 50,
		offset_x = 0,
		offset_y = 0,
		frame_count = 1,
		frame_duration = 0.0,
		texture_path = "assets/bacteria/pseudomonas.png",
	},
}
// ---- Init ----
bacteria_init :: proc(hot: ^BacteriaHot, cold: ^BacteriaCold, spawn_params: ^BacteriaSpawnParams) {
	bacteria_def := get_bacteria_def(spawn_params.species)
	hot.height = bacteria_def.height
	hot.width = bacteria_def.width
	hot.hb_height = bacteria_def.hb_height
	hot.hb_width = bacteria_def.hb_width
	hot.offset_x = bacteria_def.offset_x
	hot.offset_y = bacteria_def.offset_y
	hot.health = bacteria_def.health
	hot.active = true
	hot.species = spawn_params.species
	hot.x = spawn_params.path_data.control_points[0].x
	hot.y = spawn_params.path_data.control_points[0].y
	hot.current_frame = int(rand.int31()) % bacteria_def.frame_count
	hot.animation_timer = 0.0
	hot.angle = 0.0

	cold.speed_scalar = spawn_params.speed_scalar
	cold.speed = f32(bacteria_def.base_speed) * cold.speed_scalar
	cold.state_start_time = 0
	cold.bacteria_state = .Entering
	cold.t = 0.0
	cold.entry_path = spawn_params.path_data
	cold.formation_point = spawn_params.formation_position
	cold.dive_initialized = false
	cold.return_initialized = false
	cold.should_flee = false
	cold.current_segment = 0
	cold.pause_timer = 0.0
}

bacteria_dive_init :: proc(hot: ^BacteriaHot, cold: ^BacteriaCold, player_x: f32) {
	switch hot.species {
	case .Strep:
		cold.dive_type = Sine_Dive {
			amplitude  = 10.0,
			frequency  = 1.0,
			start_x    = hot.x,
			dive_speed = 200.0,
		}
	case .Staph:
		cold.dive_type = Scatter_Dive {
			burst_angle    = rand.float32() * math.PI,
			burst_speed    = 500.0,
			burst_pause    = 0.6,
			burst_duration = 0.4,
			timer          = 0.0,
			start_x        = hot.x,
			start_y        = hot.y,
			phase          = .Bursting,
		}
	case .Ecoli:
		cold.dive_type = Zigzag_Dive {
			direction = player_x >= hot.x ? 1 : -1,
			cooldown  = 0.2,
			timer     = 0.0,
			speed     = 300.0,
			start_x   = hot.x,
			start_y   = hot.y,
			phase     = .Dashing,
		}
	case .Pseudomonas:
		cps: [4]sdl.FPoint
		cps[0] = {hot.x, hot.y}
		cps[1] = {hot.x, hot.y + 500}
		if hot.x >= f32(SCREEN_WIDTH) / 2 {
			cps[2] = {f32(SCREEN_WIDTH) * 0.25, f32(SCREEN_HEIGHT) * 0.9}
			cps[3] = {0, f32(SCREEN_HEIGHT) + f32(hot.height)}
		} else {
			cps[2] = {f32(SCREEN_WIDTH) * 0.75, f32(SCREEN_HEIGHT) * 0.9}
			cps[3] = {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT) + f32(hot.height)}
		}
		cold.dive_type = Sweep_Dive {
			control_points = cps,
			t              = 0.0,
		}
	}
}

// ---- Update ----

bacteria_enter_update :: proc(hot: ^BacteriaHot, cold: ^BacteriaCold, delta_time: f32) {
	bacteria_def := get_bacteria_def(hot.species)

	switch hot.species {
	case .Strep:
		dx := cold.entry_path.control_points[3].x - cold.entry_path.control_points[0].x
		dy := cold.entry_path.control_points[3].y - cold.entry_path.control_points[0].y
		path_length := math.sqrt(dx * dx + dy * dy)
		cold.t += (cold.speed * delta_time) / path_length

		if cold.t >= 1.0 {
			cold.bacteria_state = .Holding
			cold.t = 1.0
			cold.state_start_time = u64(sdl.GetTicks())
			hot.x = cold.formation_point.x
			hot.y = cold.formation_point.y
		}
		tangent := bezier_tangent(cold.entry_path, cold.t)
		hot.angle = math.atan2_f32(tangent.y, tangent.x) * (180.0 / math.PI) - 90.0

		pos := bezier_calc(cold.entry_path, cold.t)
		hot.x = pos.x
		hot.y = pos.y
	case .Staph:
	case .Ecoli:
	case .Pseudomonas:
	}

}

bacteria_dive_update :: proc(
	hot: ^BacteriaHot,
	cold: ^BacteriaCold,
	delta_time: f32,
	player_x: f32,
) {
	bacteria_def := get_bacteria_def(hot.species)

	switch &dive in cold.dive_type {
	case Sine_Dive:
		dive.phase += dive.frequency * 2.0 * math.PI * delta_time
		hot.x = dive.start_x + math.sin(dive.phase) * dive.amplitude
		cycle_position := math.mod(dive.phase, 2.0 * math.PI) / (2.0 * math.PI)

		if cycle_position < 0 do cycle_position += 1.0

		hot.current_frame = int(cycle_position * f32(bacteria_def.frame_count))

		if hot.current_frame >= bacteria_def.frame_count do hot.current_frame = bacteria_def.frame_count - 1

		hot.y += dive.dive_speed * delta_time
		hot.angle =
			math.atan2(dive.dive_speed, math.cos(dive.phase) * dive.amplitude * dive.frequency) *
				(180.0 / math.PI) -
			90


		if hot.y > SCREEN_HEIGHT {
			cold.bacteria_state = .Returning
			cold.dive_initialized = false
			cold.return_start_point = {hot.x, 0 - f32(hot.height)}
			cold.t = 0.0
		}

	case Scatter_Dive:
		if dive.phase == .Bursting {
			hot.x += math.cos(dive.burst_angle) * dive.burst_speed * delta_time
			hot.y += math.sin(dive.burst_angle) * dive.burst_speed * delta_time
			dive.timer += delta_time

			if dive.timer >= dive.burst_duration {
				dive.phase = .Pausing
				dive.timer = 0.0
			}
		} else if dive.phase == .Pausing {
			dive.timer += delta_time
			if dive.timer >= dive.burst_pause {
				dive.phase = .Diving
				dive.target_x = player_x + (rand.float32() - 0.5) * 200.0
			}
		} else if dive.phase == .Diving {
			diff := dive.target_x - hot.x
			if diff > 1.0 {
				hot.x += dive.burst_speed * 0.3 * delta_time
			} else if diff < -1.0 {
				hot.x -= dive.burst_speed * 0.3 * delta_time
			}
			hot.y += delta_time * dive.burst_speed

			if hot.y > SCREEN_HEIGHT {
				cold.bacteria_state = .Returning
				cold.dive_initialized = false
			}
		}
	case Zigzag_Dive:
	case Sweep_Dive:
	}
}

bacteria_update :: proc(bacteria: ^Bacteria, delta_time: f32, player_x: f32) {
	for i in 0 ..< MAX_ENEMIES {
		if !bacteria.hot[i].active do continue

		hot := &bacteria.hot
		cold := &bacteria.cold

		def := get_bacteria_def(bacteria.hot[i].species)
		bacteria_animate(&hot[i], def, delta_time)

		switch bacteria.cold[i].bacteria_state {
		case .Entering:
			bacteria_enter_update(&hot[i], &cold[i], delta_time)
		case .Holding:
			hot[i].angle = hot[i].angle + (0.0 - hot[i].angle) * (delta_time * 3.0)
		case .Diving:
			if !bacteria.cold[i].dive_initialized {
				bacteria_dive_init(&hot[i], &cold[i], player_x)
				bacteria.cold[i].dive_initialized = true
			}
			bacteria_dive_update(&hot[i], &cold[i], delta_time, player_x)
		case .Returning:
		case .Fleeing:
		}
	}

}

// ---- Helper ----
get_bacteria_def :: proc(bacteria_species: BacteriaSpecies) -> ^BacteriaDefinition {
	return &BACTERIA_DEFS[bacteria_species]
}

find_free_bacteria_slot :: proc(bacteria: ^Bacteria) -> int {
	for i in 0 ..< MAX_ENEMIES {
		if !bacteria.hot[i].active {
			return i
		}
	}
	return -1
}

bacteria_spawn :: proc(bacteria: ^Bacteria, spawn_params: ^BacteriaSpawnParams) -> int {
	index := find_free_bacteria_slot(bacteria)
	if index == -1 {
		return -1
	}
	bacteria_init(&bacteria.hot[index], &bacteria.cold[index], spawn_params)
	return index
}

bacteria_animate :: proc(hot: ^BacteriaHot, def: ^BacteriaDefinition, delta_time: f32) {
	if def.frame_count <= 1 do return

	hot.animation_timer += delta_time
	for hot.animation_timer >= def.frame_duration {
		hot.animation_timer -= def.frame_duration
		hot.current_frame = (hot.current_frame + 1) % def.frame_count
	}
}
