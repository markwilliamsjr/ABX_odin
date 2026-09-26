package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

// ---- TYPES ----

Debug :: struct {
	debug_enabled:      bool,
	show_stats:         bool,
	show_entities:      bool,
	show_player:        bool,
	fps:                f32,
	frame_time:         f32,
	fps_timer:          f32,
	fps_frames:         int,
	frame_count:        u64,
	fps_texture:        ^sdl.Texture,
	prev_fps:           f32,
	fps_rect:           sdl.Rect,
	game_state_texture: ^sdl.Texture,
	prev_game_state:    GameState,
	game_state_rect:    sdl.Rect,
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
		debug.fps_frames = 0
		debug.fps_timer = 0.0
	}
}

// ---- RENDER ----
debug_render :: proc(debug: ^Debug, assets: ^Assets, world: ^World, renderer: ^sdl.Renderer) {
	if !debug.debug_enabled do return

	// Draw debug background
	sdl.SetRenderDrawBlendMode(renderer, .BLEND)
	sdl.SetRenderDrawColor(renderer, 10, 10, 10, 220)
	rect := sdl.Rect {
		x = 10,
		y = 10,
		w = (SCREEN_WIDTH / 3),
		h = SCREEN_HEIGHT - 20,
	}
	sdl.RenderFillRect(renderer, &rect)

	// Draw FPS
	if debug.prev_fps != debug.fps || debug.fps_texture == nil {
		fps_text := strings.clone_to_cstring(
			fmt.aprintf("FPS: %.1f", debug.fps, allocator = context.temp_allocator),
		)
		fps_surface := ttf.RenderText_Blended(assets.debug_font, fps_text, {255, 255, 255, 220})
		defer sdl.FreeSurface(fps_surface)
		sdl.DestroyTexture(debug.fps_texture)
		debug.fps_texture = sdl.CreateTextureFromSurface(renderer, fps_surface)
		fps_text_w: i32
		fps_text_h: i32
		sdl.QueryTexture(debug.fps_texture, nil, nil, &fps_text_w, &fps_text_h)

		debug.fps_rect = sdl.Rect {
			x = 15,
			y = 15,
			w = fps_text_w,
			h = fps_text_h,
		}
		debug.prev_fps = debug.fps
	}
	sdl.RenderCopy(renderer, debug.fps_texture, nil, &debug.fps_rect)

	if debug.prev_game_state != world.state || debug.game_state_texture == nil {
		game_state_text := strings.clone_to_cstring(
			fmt.aprintf("State: %v", world.state, allocator = context.temp_allocator),
		)
		game_state_surface := ttf.RenderText_Blended(
			assets.debug_font,
			game_state_text,
			{255, 255, 255, 220},
		)
		defer sdl.FreeSurface(game_state_surface)
		sdl.DestroyTexture(debug.game_state_texture)
		debug.game_state_texture = sdl.CreateTextureFromSurface(renderer, game_state_surface)
		game_state_text_w: i32
		game_state_text_h: i32
		sdl.QueryTexture(
			debug.game_state_texture,
			nil,
			nil,
			&game_state_text_w,
			&game_state_text_h,
		)
		debug.game_state_rect = sdl.Rect {
			x = 15,
			y = 15 + debug.fps_rect.h,
			w = game_state_text_w,
			h = game_state_text_h,
		}
		debug.prev_game_state = world.state
	}
	sdl.RenderCopy(renderer, debug.game_state_texture, nil, &debug.game_state_rect)
}
