package main

import "core:math"
import sdl "vendor:sdl2"

// ---- Constants ----
MAX_SEGMENTS :: 4

// ---- Types ----
PathType :: enum {
	Arc,
	Line_Ish,
	Tight_Hook,
	Wide_Sweep,
	Loop_De_Loop,
}

FormationBounds :: struct {
	x, y, width, height: f32,
}

EntryPathData :: struct {
	control_points: [MAX_SEGMENTS * 4]sdl.FPoint,
	segment_pause:  [MAX_SEGMENTS]f32,
	num_segments:   int,
	path_type:      PathType,
}

FormationResult :: struct {
	placed, remaining: int,
}

WaveParams :: struct {
	total_enemies, max_simult_divers, species_unlocked, level: int,
	speed_scalar, spawn_delay, dive_delay, threshold:          f32,
	path_type:                                                 PathType,
	formation_params:                                          FormationParams,
}

// FormationDefinition :: struct {
//	formation_type: FormationType,
//	fits:           FormationFitsFn,
//	sizes:          FormationSizeFn,
//	generate:       FormationGenFn,
//}

FormationParams :: union {
	Line_Params,
	V_Params,
	Semicircle_Params,
}

Line_Params :: struct {
	max_per_row:          int,
	row_spacing_fraction: f32,
}

V_Params :: struct {
	apex_angle: f32,
}

Semicircle_Params :: struct {
	radius_fraction: f32,
}

// ---- Data ----

// ---- Init ----

// ---- Update ----

// ---- Helper ----
level_to_params :: proc(level: int) -> WaveParams {
	// Blocks count to 5
	level_in_block := (level - 1) % 5 + 1
	block_number := (level - 1) / 5

	wp := WaveParams {
		total_enemies = 3 + (level * 2),
		species_unlocked = (level - 1) / 5 + 1,
		max_simult_divers = 1,
		spawn_delay = 0.3,
		threshold = 0.8,
		path_type = .Line_Ish,
		formation_params = Line_Params{max_per_row = -1, row_spacing_fraction = 1.0},
	}
	wp.speed_scalar = 1.0 + f32(block_number) * 0.2 + f32(level_in_block) * 0.1
	return wp
}

generate_path :: proc(
	path_type: PathType,
	start: sdl.FPoint,
	destination: sdl.FPoint,
) -> EntryPathData {
	path := EntryPathData {
		num_segments = 0,
		path_type    = path_type,
	}
	switch path_type {
	case .Arc:
		path.control_points[0] = start
		path.control_points[3] = destination

		dx := destination.x - start.x
		dy := destination.y - start.y

		path.control_points[1].x = start.x + dx * (1.0 / 3.0)
		path.control_points[1].y = start.y + dy * (1.0 / 3.0)

		path.control_points[2].x = start.x + dx * (2.0 / 3.0)
		path.control_points[2].y = start.y + dy * (2.0 / 3.0)

		offset :=
			f32(SCREEN_WIDTH) * 0.12 if start.x > f32(SCREEN_WIDTH) / 2.0 else f32(SCREEN_WIDTH) * -0.12

		path.control_points[1].x += offset
		path.control_points[2].x += offset

		path.num_segments = 1
	case .Line_Ish:
		path.control_points[0] = start
		path.control_points[3] = destination

		dx := destination.x - start.x
		dy := destination.y - start.y

		path.control_points[1].x = start.x + dx * (1.0 / 3.0)
		path.control_points[1].y = start.y + dy * (1.0 / 3.0)

		path.control_points[2].x = start.x + dx * (2.0 / 3.0)
		path.control_points[2].y = start.y + dy * (2.0 / 3.0)

		offset :=
			f32(SCREEN_WIDTH) * 0.04 if start.x > f32(SCREEN_WIDTH) / 2.0 else f32(SCREEN_WIDTH) * -0.04

		path.control_points[1].x += offset
		path.control_points[2].x += offset

		path.num_segments = 1

	case .Tight_Hook:
		path.control_points[0] = start
		path.control_points[3] = destination

		dx := destination.x - start.x
		dy := destination.y - start.y

		length := math.sqrt(dx * dx + dy * dy)

		ndx := dx / length
		ndy := dy / length

		perp_x := -ndy
		perp_y := ndx

		if (destination.x > f32(SCREEN_WIDTH) / 2.0) == (perp_x > 0) {
			// TODO Watch to see how the bacteria curls, flip condition if needed
			perp_x = -perp_x
			perp_y = -perp_y
		}

		hook_strength := f32(SCREEN_WIDTH) * 0.15 // TODO Fine tune strength
		approach := f32(0.5)

		path.control_points[1].x = start.x + dx * approach
		path.control_points[1].y = start.y + dy * approach

		path.control_points[2].x = destination.x + perp_x * hook_strength
		path.control_points[2].y = destination.y + perp_y * hook_strength

		path.num_segments = 1

	case .Wide_Sweep:
		path.control_points[0] = start
		path.control_points[3] = destination

		dx := destination.x - start.x
		dy := destination.y - start.y
		length := math.sqrt(dx * dx + dy * dy)

		ndx := dx / length
		ndy := dy / length

		perp_x := -ndy
		perp_y := ndx

		if (destination.x > f32(SCREEN_WIDTH) / 2.0) != (perp_x > 0) {
			// TODO Watch to see how the bacteria curls, flip condition if needed
			perp_x = -perp_x
			perp_y = -perp_y
		}

		sweep_width := f32(SCREEN_WIDTH) * 0.3 // TODO Fine tune: bigger number bigger arc

		path.control_points[1].x = start.x + dx * (1.0 / 3.0) + perp_x * sweep_width
		path.control_points[1].y = start.y + dy * (1.0 / 3.0) + perp_y * sweep_width

		path.control_points[2].x = start.x + dx * (2.0 / 3.0) + perp_x * sweep_width
		path.control_points[2].y = start.y + dy * (2.0 / 3.0) + perp_y * sweep_width

		path.num_segments = 1

	case .Loop_De_Loop:
	}
	return path
}
