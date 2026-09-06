package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import sdl "vendor:sdl2"
import sdl_image "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

// ---- Consants ----

SDL_FLAGS :: sdl.INIT_EVERYTHING
WINDOW_TITLE :: "ABX!"
WINDOW_FLAGS :: sdl.WINDOW_SHOWN
RENDERER_FLAGS :: sdl.RENDERER_ACCELERATED | sdl.RENDERER_PRESENTVSYNC

SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 360
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

WEAPON_COUNT :: 50
MAX_BULLETS :: 50
MAX_ENEMIES :: 50
MAX_WAVES :: 10
MAX_REGIONS :: 4

// ---- Types ----

Game :: struct {
	window:      ^sdl.Window,
	renderer:    ^sdl.Renderer,
	assets:      Assets,
	world:       World,
	debug:       Debug,
	config:      Config,
	master_seed: u64,
}

World :: struct {
	player:   Player,
	bullets:  Bullets,
	bacteria: Bacteria,
	level:    Level,
	state:    GameState,
}

Assets :: struct {
	ships:      [WeaponType]^sdl.Texture,
	bullets:    [WeaponType]^sdl.Texture,
	bacteria:   [BacteriaSpecies]^sdl.Texture,
	debug_font: ^ttf.Font,
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
		// fmt.eprintfln("Error initializing SDL2: %s", sdl.GetError())
		return false
	}
	if ttf.Init() != 0 {
		return false
	}
	g.window = sdl.CreateWindow(
		WINDOW_TITLE,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		WINDOW_FLAGS,
	)
	if g.window == nil {
		// fmt.eprintfln("Error creating window: %s", sdl.GetError())
		return false
	}
	sdl.SetHint(sdl.HINT_RENDER_SCALE_QUALITY, "0")
	g.renderer = sdl.CreateRenderer(g.window, -1, RENDERER_FLAGS)
	sdl.RenderSetLogicalSize(g.renderer, SCREEN_WIDTH, SCREEN_HEIGHT)
	if g.renderer == nil {
		// fmt.eprintfln("Error creating renderer: %s", sdl.GetError())
		return false
	}
	img_flags := sdl_image.INIT_PNG
	if (sdl_image.Init(img_flags) & img_flags) != img_flags {
		// fmt.eprintfln("SDL image initialization failted %s\n", sdl_image.GetError())
		return false
	}
	return true
}

game_init :: proc(game: ^Game) {
	now := time.now()
	game.master_seed = u64(time.time_to_unix_nano(now))
	fmt.println("Master Seed: ", game.master_seed)
	assets_init(&game.assets, game.renderer)
	world_init(&game.world, game.master_seed)
	debug_init(&game.debug)
}

world_init :: proc(world: ^World, seed: u64) {
	world.state = .Menu
	world.player = player_init(SCREEN_WIDTH, SCREEN_HEIGHT)
	level_init(&world.bacteria, &world.level, seed)
}

assets_init :: proc(asset: ^Assets, renderer: ^sdl.Renderer) {
	for kind in WeaponType {
		def := get_weapon_def(kind)
		asset.ships[kind] = image_texture_load(renderer, def.ship_texture_path)
		if asset.ships[kind] != nil {
			// fmt.println(kind, "Ship Loaded")
		}
		asset.bullets[kind] = image_texture_load(renderer, def.bullet_texture_path)
		if asset.bullets[kind] != nil {
			// fmt.println(kind, "Bullet Loaded")
		}
	}
	for bacteria in BacteriaSpecies {
		def := get_bacteria_def(bacteria)
		asset.bacteria[bacteria] = image_texture_load(renderer, def.texture_path)
		if asset.bacteria[bacteria] != nil {
			// fmt.println(bacteria, "Texture Loaded")
		}
	}
	debug_font_path := "assets/fonts/mono.ttf"
	asset.debug_font = ttf.OpenFont(
		strings.clone_to_cstring(debug_font_path, context.temp_allocator),
		16,
	)
	if asset.debug_font == nil do fmt.println("Debug Font not found")
}

// ---- Update ----

game_handle_events :: proc(game: ^Game, event: ^sdl.Event, running: ^bool) {
	for (sdl.PollEvent(event)) {
		#partial switch event.type {
		case .QUIT:
			running^ = false

		case .WINDOWEVENT:
			if event.window.event == .CLOSE do running^ = false

		case .KEYDOWN:
			#partial switch event.key.keysym.sym {
			case .ESCAPE:
				running^ = false
			case .F3:
				game.debug.debug_enabled = !game.debug.debug_enabled
			}
		}
	}
}

collision_update :: proc(bullet: ^Bullets, bacteria: ^Bacteria) {
	for i := bullet.count - 1; i >= 0; i -= 1 {
		for j in 0 ..< MAX_ENEMIES {
			hot := &bacteria.hot[j]
			cold := &bacteria.cold[j]
			bacteria_def := get_bacteria_def(hot.species)
			weapon_def := get_weapon_def(bullet.weapon_type[i])
			if !hot.active do continue
			collision := check_collision(
				{hot.x, hot.y},
				hot.hb_width,
				hot.hb_height,
				{bullet.x[i], bullet.y[i]},
				bullet.width[i],
				bullet.height[i],
			)
			if collision {
				hot.health -= calculate_bullet_damage(weapon_def^, bacteria_def^)
				if hot.health <= 0 {
					hot.active = false
				}
				bullet_remove(bullet, i)
				break
			}
		}
	}
}

// ---- Helper ----

image_texture_load :: proc(renderer: ^sdl.Renderer, path: string) -> ^sdl.Texture {
	if path == "" {
		// fmt.eprintfln("Texture load called NULL path\n")
		return nil
	}

	surface := sdl_image.Load(strings.clone_to_cstring(path, context.temp_allocator))
	if surface == nil {
		// fmt.eprintfln("Unable to load image: %s", sdl_image.GetError())
		return nil
	}

	defer sdl.FreeSurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		// fmt.eprintfln("Unable to create texture from surface: SDL Error: %s", sdl_image.GetError())
		return nil
	}
	return texture
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

calculate_bullet_damage :: proc(
	weapon_def: WeaponDefinition,
	bacteria_def: BacteriaDefinition,
) -> int {
	if weapon_def.weapon_type == .Neutral {
		return weapon_def.damage_neutral
	}
	if weapon_def.weapon_type == bacteria_def.weakness {
		return weapon_def.damage_effective
	}
	return weapon_def.damage_ineffective
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
	if assets.debug_font != nil do ttf.CloseFont(assets.debug_font)
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
	ttf.Quit()
	sdl_image.Quit()
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

	// GAME LOOP

	for running {
		current_time := sdl.GetTicks()
		delta_time := f32(current_time - last_time) / 1000.0
		last_time = current_time

		game_handle_events(&game, &event, &running)
		keystate := sdl.GetKeyboardState(nil)

		// DEBUG UPDATES
		debug_update(&game.debug, delta_time)

		// GAME UPDATES
		player_update(&game.world.player, keystate, delta_time)
		player_fire_bullet(&game.world.player, &game.world.bullets, keystate)
		bullet_update(&game.world.bullets, delta_time)
		bacteria_update(&game.world.bacteria, delta_time, game.world.player.x)
		collision_update(&game.world.bullets, &game.world.bacteria)
		wave_update(&game.world.level.wave[0], &game.world.bacteria, delta_time)
		wave_dive_update(&game.world.level.wave[0], &game.world.bacteria, delta_time)

		// RENDER
		render_world(&game.world, &game.assets, game.renderer)
		debug_render(&game.debug, &game.assets, game.renderer)
		sdl.RenderPresent(game.renderer)
	}
}
