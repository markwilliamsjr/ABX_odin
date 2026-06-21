package main

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl2"
import sdl_image "vendor:sdl2/image"

// ---- Consants ----

SDL_FLAGS :: sdl.INIT_EVERYTHING
WINDOW_TITLE :: "ABX!"
WINDOW_FLAGS :: sdl.WINDOW_SHOWN
RENDERER_FLAGS :: sdl.RENDERER_ACCELERATED | sdl.RENDERER_PRESENTVSYNC
SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720
WEAPON_COUNT :: 50
MAX_BULLETS :: 50
MAX_ENEMIES :: 50
MAX_WAVES :: 10

// ---- Types ----

Game :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
	assets:  Assets,
	world: World,
}

World :: struct {
	player:  Player,
	bullets: Bullets,
	state:   GameState,
}

Assets :: struct {
	ships:   [WeaponType]^sdl.Texture,
	bullets: [WeaponType]^sdl.Texture,
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

world_init :: proc(world: ^World, renderer: ^sdl.Renderer) {
	assets_init(&world.assets, renderer)
	world.state = .Menu
	world.player = player_init(SCREEN_WIDTH, SCREEN_HEIGHT)

	for i in 0 ..< WEAPON_COUNT {
		world.bullets[i].active = false
	}
}

assets_init :: proc(asset: ^Assets, renderer: ^sdl.Renderer) {
	for kind in WeaponType {
		def := get_weapon_def(kind)
		asset.ships[kind] = texture_load(renderer, def.ship_texture_path)
		asset.bullets[kind] = texture_load(renderer, def.bullet_texture_path)
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
		if event.type == .KEYDOWN && event.key.keysym.sym == .p {
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

// ---- Render ----

render_world :: proc(world: ^World, renderer: ^sdl.Renderer) {
	sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
	sdl.RenderClear(renderer)

	if world.player.active {
		sdl.SetRenderDrawColor(renderer, 255, 0, 0, 0)
		player := sdl.Rect {
			x = i32(world.player.x),
			y = i32(world.player.y),
			w = i32(world.player.width),
			h = i32(world.player.height),
		}
		sdl.RenderDrawRect(renderer, &player)
		sdl.RenderFillRect(renderer, &player)
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
	assets_destroy(&world.assets)
}

game_cleanup :: proc(g: ^Game) {
	if g != nil {
		if g.renderer != nil do sdl.DestroyRenderer(g.renderer)
		if g.window != nil do sdl.DestroyWindow(g.window)
		sdl.Quit()
	}
	sdl.Quit()
}

// ---- Main ----

main :: proc() {
	exit_status := 0
	game: Game
	world: World

	defer {
		world_cleanup(&world)
		game_cleanup(&game)
		os.exit(exit_status)
	}

	if !initialize_sdl(&game) {
		exit_status = 1
		return
	}
	world_init(&world, game.renderer)

	event: sdl.Event
	last_time := sdl.GetTicks()
	running := true

	// GAME LOOP

	for running {
		current_time := sdl.GetTicks()
		delta_time := f32(current_time - last_time) / 1000.0
		last_time = current_time

		world_handle_events(&world, &event, &running)
		keystate := sdl.GetKeyboardState(nil)

		/* 
     * Player Update will eventually be merged into a game update
     * that will handle players, enemies, and level updates
     */

		player_update(&world.player, keystate, delta_time)
		render_world(&world, game.renderer)
		sdl.RenderPresent(game.renderer)
	}
}
