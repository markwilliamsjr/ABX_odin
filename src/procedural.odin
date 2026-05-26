package main

import sdl "vendor:sdl2"

// ---- Types ----
FormationType :: enum {
    Line,
    V,
    Stagger,
    Diamond,
    Hexagon,
    Semicircle,
}

PathType :: enum {
    Arc,
    Line-ish,
    Tight_Hook,
    Wide_Sweep,
    Loop_De_Loop
}

FormationBounds :: struct {
    x, y, width, height: f32
}

EntryPathData :: struct {
    control_points: [8]sdl.FPoint,
    num_segments: int,
    path_type: PathType
}

FormationResult :: struct {
    placed, remaining: int
}

WaveParams :: struct {
    total_enemies, max_simult_divers, species_unlocked, level: int,
    speed_scalar, spawn_delay, dive_delay, threshold: f32,
    path_type: PathType,
    formation_type: FormationType,
    formation_params: FormationParams,
}

FormationDefinition :: struct {
    formation_type: FormationType,
    fits: FormationFitsFn,
    sizes: FormationSizeFn,
    generate: FormationGenFn
}

FormationResult :: union {
    line :: struct {
        max_per_row: int,
        row_spacing_fraction: f32,
    },
    v :: struct {
        apex_angle: f32,
    },
    semicircle :: struct {
        radius_fraction: f32,
    },
    diamond :: struct {
        aspect_ratio: f32,
    },
}