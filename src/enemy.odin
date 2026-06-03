package main

import sdl "vendor:sdl2"
// ---- Constants ----

// ---- Types ----

Dive_Type :: enum {
	Sine,
	Scatter,
	Zigzag,
	Sweep,
}

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

// ---- Data ----
// ---- Init ----
// ---- Update ----
// ---- Helper ----
