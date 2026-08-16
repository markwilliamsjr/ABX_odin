package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import sdl "vendor:sdl2"
import sdl_image "vendor:sdl2/image"

// ---- Consants ----

SDL_FLAGS :: sdl.INIT_EVERYTHING
WINDOW_TITLE :: "ABX!"
WINDOW_FLAGS :: sdl.WINDOW_SHOWN
RENDERER_FLAGS :: sdl.RENDERER_ACCELERATED | sdl.RENDERER_PRESENTVSYNC
SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 360
WEAPON_COUNT :: 50
MAX_BULLETS :: 50
MAX_ENEMIES :: 50
MAX_WAVES :: 10
MAX_REGIONS :: 4

// ---- Types ----

Game :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
	assets:   Assets,
	world:    World,
}

World :: struct {
	player:   Player,
	bullets:  Bullets,
	bacteria: Bacteria,
	level:    Level,
	state:    GameState,
}

Assets :: struct {
	ships:    [WeaponType]^sdl.Texture,
	bullets:  [WeaponType]^sdl.Texture,
	bacteria: [BacteriaSpecies]^sdl.Texture,
}

GameState :: enum {
	Menu,
	Playing,
	Level_Transition,
	Paused,
	Game_Over,
}

// ---- Init ----

initialize_sdl :: proc(g: ^Game) -> bool {
	if sdl.Init(SDL_FLAGS) != 0 {
		fmt.eprintfln("Error initializing SDL2: %s", sdl.GetError())
		return false
	}
	g.window = sdl.CreateWindow(
		WINDOW_TITLE,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		WINDOW_FLAGS,
	)
	if g.window == nil {
		fmt.eprintfln("Error creating window: %s", sdl.GetError())
		return false
	}
	g.renderer = sdl.CreateRenderer(g.window, -1, RENDERER_FLAGS)
	if g.renderer == nil {
		fmt.eprintfln("Error creating renderer: %s", sdl.GetError())
		return false
	}
	img_flags := sdl_image.INIT_PNG
	if (sdl_image.Init(img_flags) & img_flags) != img_flags {
		fmt.eprintfln("SDL image initialization failted %s\n", sdl_image.GetError())
		return false
	}
	return true
}

game_init :: proc(game: ^Game) {
	assets_init(&game.assets, game.renderer)
	world_init(&game.world)
}

world_init :: proc(world: ^World) {
	world.state = .Menu
	world.player = player_init(SCREEN_WIDTH, SCREEN_HEIGHT)
	level_init(&world.bacteria, &world.level)
}

assets_init :: proc(asset: ^Assets, renderer: ^sdl.Renderer) {
	for kind in WeaponType {
		def := get_weapon_def(kind)
		asset.ships[kind] = texture_load(renderer, def.ship_texture_path)
		if asset.ships[kind] != nil {
			fmt.println(kind, "Ship Loaded")
		}
		asset.bullets[kind] = texture_load(renderer, def.bullet_texture_path)
		if asset.bullets[kind] != nil {
			fmt.println(kind, "Bullet Loaded")
		}
	}
	for bacteria in BacteriaSpecies {
		def := get_bacteria_def(bacteria)
		asset.bacteria[bacteria] = texture_load(renderer, def.texture_path)
		if asset.bacteria[bacteria] != nil {
			fmt.println(bacteria, "Texture Loaded")
		}
	}
}

// ---- Update ----

world_handle_events :: proc(world: ^World, event: ^sdl.Event, running: ^bool) {
	for (sdl.PollEvent(event)) {
		if event.type == .QUIT {
			running^ = false
		}
		if event.type == .WINDOWEVENT && event.window.event == .CLOSE {
			running^ = false
		}
		if event.type == .KEYDOWN && event.key.keysym.sym == .ESCAPE {
			running^ = false
		}
	}
}

// ---- Helper ----

texture_load :: proc(renderer: ^sdl.Renderer, path: string) -> ^sdl.Texture {
	if path == "" {
		fmt.eprintfln("Texture load called NULL path\n")
		return nil
	}

	surface := sdl_image.Load(strings.clone_to_cstring(path, context.temp_allocator))
	if surface == nil {
		fmt.eprintfln("Unable to load image: %s", sdl_image.GetError())
		return nil
	}

	defer sdl.FreeSurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		fmt.eprintfln("Unable to create texture from surface: SDL Error: %s", sdl_image.GetError())
		return nil
	}
	return texture
}

player_fire_bullet :: proc(player: ^Player, bullet: ^Bullets, keystate: [^]u8) {
	if keystate[sdl.SCANCODE_SPACE] != 0 && !player.was_firing {
		player.was_firing = true
		bullet_spawn(bullet, player)
	}
	if keystate[sdl.SCANCODE_SPACE] == 0 {
		player.was_firing = false
	}
}

// ---- Math ----

bezier_calc :: proc(path_data: EntryPathData, t: f32) -> sdl.FPoint {
	result: sdl.FPoint

	one_minus_t := 1.0 - t
	omt_2 := one_minus_t * one_minus_t
	omt_3 := omt_2 * one_minus_t
	t2 := t * t
	t3 := t2 * t
	result.x =
		omt_3 * path_data.control_points[0].x +
		3 * omt_2 * t * path_data.control_points[1].x +
		3 * one_minus_t * t2 * path_data.control_points[2].x +
		t3 * path_data.control_points[3].x
	result.y =
		omt_3 * path_data.control_points[0].y +
		3 * omt_2 * t * path_data.control_points[1].y +
		3 * one_minus_t * t2 * path_data.control_points[2].y +
		t3 * path_data.control_points[3].y
	return result
}

calculate_bezier_angle :: proc(path_data: EntryPathData, t: f32) -> f32 {
	points := path_data.control_points
	result: sdl.FPoint
	u := 1.0 - t
	uu := u * u
	tt := t * t
	ut6 := 6.0 * u * t

	result.x =
		3.0 * uu * (points[1].x - points[0].x) +
		ut6 * (points[2].x - points[1].x) +
		3.0 * tt * (points[3].x - points[2].x)
	result.y =
		3.0 * uu * (points[1].y - points[0].y) +
		ut6 * (points[2].y - points[1].y) +
		3.0 * tt * (points[3].y - points[2].y)

	return math.atan2_f32(result.y, result.x) * (180.0 / math.PI) - 90.0
}

estimate_bezier_arc_length :: proc(path: EntryPathData, samples: int = 20) -> f32 {
	length := 0.0
	prev := bezier_calc(path, 0)
	for i in 1 ..= samples {
		t := f32(i) / f32(samples)
		pt := bezier_calc(path, t)
		dx := pt.x - prev.x
		dy := pt.y - prev.y
		length += math.sqrt_f64(f64(dx * dx + dy * dy))
		prev = pt
	}
	return f32(length)
}

check_collision :: proc(
	obj_1_points: sdl.FPoint,
	obj_1_width: int,
	obj_1_height: int,
	obj_2_points: sdl.FPoint,
	obj_2_width: int,
	obj_2_height: int,
) -> bool {
	if obj_1_points.x + f32(obj_1_width) <= obj_2_points.x ||
	   obj_2_points.x + f32(obj_2_width) <= obj_1_points.x {
		return false
	}
	if obj_1_points.y + f32(obj_1_height) <= obj_2_points.y ||
	   obj_2_points.y + f32(obj_2_height) <= obj_1_points.y {
		return false
	}
	return true
}

// ---- Render ----

render_world :: proc(world: ^World, assets: ^Assets, renderer: ^sdl.Renderer) {
	sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
	sdl.RenderClear(renderer)

	render_player(world, assets, renderer)
	render_bullets(world, assets, renderer)
	render_bacteria(world, assets, renderer)
}

render_player :: proc(world: ^World, assets: ^Assets, renderer: ^sdl.Renderer) {
	if world.player.active {
		player := sdl.Rect {
			x = i32(world.player.x),
			y = i32(world.player.y),
			w = i32(world.player.width),
			h = i32(world.player.height),
		}
		sdl.SetTextureBlendMode(assets.ships[world.player.current_ammo], .BLEND)
		sdl.RenderCopy(renderer, assets.ships[world.player.current_ammo], nil, &player)
	}
}

render_bullets :: proc(world: ^World, assets: ^Assets, renderer: ^sdl.Renderer) {
	for i in 0 ..< world.bullets.count {
		wep_def := get_weapon_def(world.bullets.weapon_type[i])
		bullet := sdl.Rect {
			x = i32(world.bullets.x[i]),
			y = i32(world.bullets.y[i]),
			w = i32(wep_def.width),
			h = i32(wep_def.height),
		}
		sdl.RenderCopy(renderer, assets.bullets[world.bullets.weapon_type[i]], nil, &bullet)
	}
}

render_bacteria :: proc(world: ^World, assets: ^Assets, renderer: ^sdl.Renderer) {
	for i in 0 ..< MAX_ENEMIES {
		if !world.bacteria.hot[i].active do continue

		hot := world.bacteria.hot[i]

		def := get_bacteria_def(hot.species)
		texture := assets.bacteria[hot.species]

		dst := sdl.Rect {
			x = i32(hot.x),
			y = i32(hot.y),
			w = i32(hot.width),
			h = i32(hot.height),
		}

		if texture != nil {
			src := sdl.Rect {
				x = i32(hot.current_frame) * i32(def.width),
				y = 0,
				w = i32(def.width),
				h = i32(def.height),
			}
			sdl.RenderCopyEx(renderer, texture, &src, &dst, f64(hot.angle), nil, .NONE)
		} else {
			sdl.SetRenderDrawColor(renderer, def.r, def.g, def.b, 255)
			sdl.RenderFillRect(renderer, &dst)
		}
	}
}

// ---- Clean Up ----

assets_destroy :: proc(assets: ^Assets) {
	for kind in WeaponType {
		if assets.ships[kind] != nil {
			sdl.DestroyTexture(assets.ships[kind])
			assets.ships[kind] = nil
		}
		if assets.bullets[kind] != nil {
			sdl.DestroyTexture(assets.bullets[kind])
			assets.bullets[kind] = nil
		}
	}
}

world_cleanup :: proc(world: ^World) {
}

game_cleanup :: proc(g: ^Game) {
	if g != nil {
		world_cleanup(&g.world)
		assets_destroy(&g.assets)
		if g.renderer != nil do sdl.DestroyRenderer(g.renderer)
		if g.window != nil do sdl.DestroyWindow(g.window)
	}
	sdl.Quit()
}

// ---- Main ----

main :: proc() {
	exit_status := 0
	game: Game

	defer {
		game_cleanup(&game)
		os.exit(exit_status)
	}

	if !initialize_sdl(&game) {
		exit_status = 1
		return
	}
	game_init(&game)

	event: sdl.Event
	last_time := sdl.GetTicks()
	running := true
	fps_timer: f32 = 0.0

	// GAME LOOP

	for running {
		current_time := sdl.GetTicks()
		delta_time := f32(current_time - last_time) / 1000.0
		last_time = current_time

		fps_timer += delta_time
		if fps_timer >= 1.0 {
			fmt.printfln("FPS: %.1f", 1.0 / delta_time)
			fps_timer = 0.0
		}

		world_handle_events(&game.world, &event, &running)
		keystate := sdl.GetKeyboardState(nil)

		/* 
     * Player Update will eventually be merged into a game update
     * that will handle players, enemies, and level updates
     */

		player_update(&game.world.player, keystate, delta_time)
		player_fire_bullet(&game.world.player, &game.world.bullets, keystate)
		bullet_update(&game.world.bullets, delta_time)
		bacteria_update(&game.world.bacteria, delta_time, game.world.player.x)
		wave_update(&game.world.level.wave[0], &game.world.bacteria, delta_time)
		wave_dive_update(&game.world.level.wave[0], &game.world.bacteria, delta_time)
		render_world(&game.world, &game.assets, game.renderer)
		sdl.RenderPresent(game.renderer)
	}
}
