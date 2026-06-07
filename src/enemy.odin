package main

import sdl "vendor:sdl2"
// ---- Constants ----

// ---- Types ----
Bacteria_Species :: enum {
	Strep,
	Staph,
	Ecoli,
	Pseudomonas,
}

Scatter_Phase :: enum {
	Bursting,
	Pausing,
	Dashing,
}

Zigzag_Phase :: enum {
	Dashing,
	Pausing,
}

Sine_Dive :: struct {
	phase:      f32,
	amplitude:  f32,
	freqency:   f32,
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

BacteriaDefinition :: struct {
	species:             Bacteria_Species,
	weakness:            WeaponType,
	r, g, b:             u8,
	health, base_speed:  int,
	width, height:       int,
	hb_width, hb_height: int,
	offset_x, offset_y:  int,
	framecount:          int,
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
    x, y, animation_timer, angle: f32,
    width, height, hb_width, hb_height: int,
    offset_x, offset_y, health, current_frame: int,
    active: bool, 
    species: Bacteria_Species 
}

BacteriaCold :: struct {
	bacteria_state: BacteriaState,
    dive_type: DiveType,
    entry_path: EntryPathData,
    current_segment: int,
	pause_timer: f32,
    state_start_time: u64,
    t, speed, speed_scalar: f32,
    dive_initialized, return_initialized, should_flee: bool,
    formation_point, return_start_point: sdl.FPoint
}

// ---- Definitions / Table ----

BACTERIA_DEFS := [BacteriaSpecies]BacteriaDefinition {
    .Strep = {
        species = .Strep,
        weakness = .PCN,
		dive_type = .Sine_Dive,
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
        texture_path = "assets/bacteria/strep.png"
    },
	.Staph = {
		species = .Staph,
		weakness = .PCN,
		dive_type = .Scatter_Dive,
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
		texture_path = "assets/bacteria/staph.png"
	},
	.Ecoli = {
		species = .Ecoli,
		weakness = .PMX,
		dive_type = .Zigzag_Dive,
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
		texture_path = "assets/bacteria/ecoli"
	},
	.Pseudomonas = {
		species = .Pseudomonas,
		weakness = .PMX,
		dive_type = . Sweep_Dive,
		r = 0,
		g = 200,
		b = 200,
		health = 6,
		speed = 400.0,
		width = 50,
		height = 50,
		hb_width = 50,
		hb_height = 50,
		offset_x = 0,
		offset_y = 0,
		texture_path = "assets/bacteria/pseudomonas.png"
	},
}

// ---- Data ----
// ---- Init ----
// ---- Update ----
// ---- Helper ----
