package main

import "core:fmt"
import sdl "vendor:sdl2"

// ---- TYPES ----

Debug :: struct {
	debug_enabled: bool,
	show_stats:    bool,
	show_entities: bool,
	show_player:   bool,
	fps:           f32,
	frame_time:    f32,
	fps_timer:     f32,
	fps_frames:    int,
	frame_count:   u64,
}

// ---- INIT ----
debug_init :: proc(debug: ^Debug) {
    debug.debug_enabled = true      
}

// ---- UPDATE ----
debug_update :: proc(debug: ^Debug, delta_time: f32) {
	debug.fps_frames += 1
	debug.fps_timer += delta_time

	if debug.fps_timer >= 1.0 {
		debug.fps = f32(debug.fps_frames) / debug.fps_timer
		fmt.println("FPS: ", debug.fps)
		debug.fps_frames = 0
		debug.fps_timer = 0.0
	}
}

// ---- RENDER ----
debug_render :: proc(debug: ^Debug, renderer: ^sdl.Renderer) {
	if !debug.debug_enabled do return

    sdl.SetRenderDrawBlendMode(renderer, .BLEND)
    sdl.SetRenderDrawColor(renderer, 10, 10, 10, 220)
    rect := sdl.Rect{x = 10, y = 10, w = (SCREEN_WIDTH / 3), h = SCREEN_HEIGHT-20,}
    sdl.RenderFillRect(renderer, &rect)
}
