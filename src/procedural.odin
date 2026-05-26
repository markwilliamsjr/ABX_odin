package main

import sdl "vendor:sdl2"

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
	control_points: [8]sdl.FPoint,
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
  max_per_row: int,
  row_spacing_fraction: f32 
}

V_Params :: struct {
  apex_angle: f32 
}

Semicircle_Params :: struct {
  radius_fraction: f32
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
    formation_params = Line_Params{
      max_per_row = -1,
      row_spacing_fraction = 1.0,
    },
  }
  wp.speed_scalar = 1.0 + f32(block_number) * 0.2 + f32(level_in_block) * 0.1  
  return wp
}

generate_path :: proc(path_type: PathType, start: sdl.FPoint, destination: sdl.FPoint) -> EntryPathData {
  path := EntryPathData {
    num_segments = 0,
    path_type = path_type,
  }
  switch path_type {
  case .Arc:
    path.control_points[0] = start
    path.control_points[3] = destination

    dx := destination.x - start.x 
    dy := destination.y - start.y


  case .Line_Ish:

  case .Tight_Hook:

  case .Wide_Sweep:

  case .Loop_De_Loop:
  }
  return path
}
