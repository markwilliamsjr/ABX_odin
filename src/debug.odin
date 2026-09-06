package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

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
debug_render :: proc(debug: ^Debug, assets: ^Assets, renderer: ^sdl.Renderer) {
	if !debug.debug_enabled do return

	sdl.SetRenderDrawBlendMode(renderer, .BLEND)
	sdl.SetRenderDrawColor(renderer, 10, 10, 10, 220)
	rect := sdl.Rect {
		x = 10,
		y = 10,
		w = (SCREEN_WIDTH / 3),
		h = SCREEN_HEIGHT - 20,
	}
	sdl.RenderFillRect(renderer, &rect)

	fps_text := strings.clone_to_cstring(fmt.aprintf("FPS: %.1f", debug.fps))

	fps_surface := ttf.RenderText_Blended(assets.debug_font, fps_text, {255, 255, 255, 220})
	defer sdl.FreeSurface(fps_surface)

	fps_texture := sdl.CreateTextureFromSurface(renderer, fps_surface)
	defer sdl.DestroyTexture(fps_texture)
	fps_text_w: i32
	fps_text_h: i32
	sdl.QueryTexture(fps_texture, nil, nil, &fps_text_w, &fps_text_h)

	fps_text_rect := sdl.Rect {
		x = 15,
		y = 15,
		w = fps_text_w,
		h = fps_text_h,
	}
	sdl.RenderCopy(renderer, fps_texture, nil, &fps_text_rect)}
