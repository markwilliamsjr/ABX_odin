package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

// ---- TYPES ----

Debug :: struct {
	debug_enabled:              bool,
	show_stats:                 bool,
	show_entities:              bool,
	show_player:                bool,
	fps:                        f32,
	frame_time:                 f32,
	fps_timer:                  f32,
	fps_frames:                 int,
	frame_count:                u64,
	//
	//threshold permille debug info
	//
	threshold_permille_texture: ^sdl.Texture,
	prev_threshold_permille:    int,
	threshhold_permille_rect:   sdl.Rect,
	//
	// fps debug info
	//
	fps_texture:                ^sdl.Texture,
	prev_fps:                   f32,
	fps_rect:                   sdl.Rect,
	//
	// game state debug info
	//
	game_state_texture:         ^sdl.Texture,
	prev_game_state:            GameState,
	game_state_rect:            sdl.Rect,
	//
	// wave debug info
	//
	wave_count_texture:         ^sdl.Texture,
	prev_wave_count:            int,
	wave_count_rect:            sdl.Rect,
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
		debug_update_text(
			renderer,
			assets.debug_font,
			fps_text,
			&debug.fps_texture,
			&debug.fps_rect,
			15,
			15,
		)
		debug.prev_fps = debug.fps
	}
	sdl.RenderCopy(renderer, debug.fps_texture, nil, &debug.fps_rect)

	// Draw game state
	if debug.prev_game_state != world.state || debug.game_state_texture == nil {
		game_state_text := strings.clone_to_cstring(
			fmt.aprintf("State: %v", world.state, allocator = context.temp_allocator),
		)
		debug_update_text(
			renderer,
			assets.debug_font,
			game_state_text,
			&debug.game_state_texture,
			&debug.game_state_rect,
			15,
			15 + debug.fps_rect.h,
		)
		debug.prev_game_state = world.state
	}
	sdl.RenderCopy(renderer, debug.game_state_texture, nil, &debug.game_state_rect)

	// draw wave count
	if debug.prev_wave_count != world.level.wave_count || debug.wave_count_texture == nil {
		wave_count_text := strings.clone_to_cstring(
			fmt.aprintf(
				"Wave Count: %d",
				world.level.wave_count,
				allocator = context.temp_allocator,
			),
		)
		debug_update_text(
			renderer,
			assets.debug_font,
			wave_count_text,
			&debug.wave_count_texture,
			&debug.wave_count_rect,
			15,
			15 + debug.fps_rect.h + debug.game_state_rect.h,
		)
		debug.prev_wave_count = world.level.wave_count
	}
	sdl.RenderCopy(renderer, debug.wave_count_texture, nil, &debug.wave_count_rect)

	// Draw Threshold
	if debug.prev_threshold_permille != world.level.wave[0].threshold_permille ||
	   debug.threshold_permille_texture == nil {
		threshold_permille_text := strings.clone_to_cstring(
			fmt.aprintf(
				"Threshold: %d",
				world.level.wave[0].threshold_permille,
				allocator = context.temp_allocator,
			),
		)
		debug_update_text(
			renderer,
			assets.debug_font,
			threshold_permille_text,
			&debug.threshold_permille_texture,
			&debug.threshhold_permille_rect,
			15,
			15 + debug.fps_rect.h + debug.game_state_rect.h + debug.wave_count_rect.h,
		)
		debug.prev_threshold_permille = world.level.wave[0].threshold_permille
	}
	sdl.RenderCopy(
		renderer,
		debug.threshold_permille_texture,
		nil,
		&debug.threshhold_permille_rect,
	)
}

debug_update_text :: proc(
	renderer: ^sdl.Renderer,
	font: ^ttf.Font,
	text: cstring,
	texture: ^^sdl.Texture,
	rect: ^sdl.Rect,
	x, y: i32,
) {
	surface := ttf.RenderText_Blended(font, text, {255, 255, 255, 220})
	defer sdl.FreeSurface(surface)
	sdl.DestroyTexture(texture^)
	texture^ = sdl.CreateTextureFromSurface(renderer, surface)

	text_w: i32
	text_h: i32
	sdl.QueryTexture(texture^, nil, nil, &text_w, &text_h)

	rect^ = sdl.Rect {
		x = x,
		y = y,
		w = text_w,
		h = text_h,
	}
}
