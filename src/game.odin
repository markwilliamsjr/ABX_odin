package main

import "core:fmt"
import "core:os"
import sdl "vendor:sdl2"

SDL_FLAGS :: sdl.INIT_EVERYTHING
WINDOW_TITLE :: "ABX!"
WINDOW_FLAGS :: sdl.WINDOW_SHOWN
RENDERER_FLAGS :: sdl.RENDERER_ACCELERATED | sdl.RENDERER_PRESENTVSYNC
SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720
MAX_WAVES :: 10

Game :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
}

World :: struct {
	player: Player,
}

GameState :: enum {
	STATE_MENU,
	STATE_PLAYING,
	STATE_LEVEL_TRANSITION,
	STATE_PAUSED,
	STATE_GAME_OVER,
}

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
	return true
}

game_cleanup :: proc(g: ^Game) {
	if g != nil {
		if g.renderer != nil do sdl.DestroyRenderer(g.renderer)
		if g.window != nil do sdl.DestroyWindow(g.window)
		sdl.Quit()
	}
	sdl.Quit()
}

world_init :: proc(world: ^World, renderer: ^sdl.Renderer) {
	world.player = player_create(SCREEN_WIDTH, SCREEN_HEIGHT)
}

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

	world: World
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
