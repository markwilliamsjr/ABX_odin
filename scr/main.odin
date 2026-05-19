package main

import "core:fmt"
import "core:os"
import sdl "vendor:sdl2"

SDL_FLAGS :: sdl.INIT_EVERYTHING
WINDOW_TITLE :: "ABX!"
WINDOW_FLAGS :: sdl.WINDOW_SHOWN
RENDERER_FLAGS :: sdl.RENDERER_ACCELERATED | sdl.RENDERER_PRESENTVSYNC
SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 360


Game :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
}

game_cleanup :: proc(g: ^Game) {
	if g != nil {
		if g.renderer != nil do sdl.DestroyRenderer(g.renderer)
		if g.window != nil do sdl.DestroyWindow(g.window)

		sdl.Quit()
	}

}

GameStateMode :: enum {
	STATE_MENU,
	STATE_PLAYING,
	STATE_LEVEL_TRANSITION,
	STATE_PAUSED,
	STATE_GAME_OVER,
}

/*
GameState :: struct {
	player:  Player,
	bullets: []Bullets,
	enemy:   []Enemy,
	level:   Level,
	assets:  Assets,
	mode:    GameState_Mode,
}
*/

initialize :: proc(g: ^Game) -> bool {
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

main :: proc() {
	exit_status := 0
	game: Game

	defer {
		game_cleanup(&game)
		os.exit(exit_status)
	}

	if !initialize(&game) {
		exit_status = 1
		return
	}

	event: sdl.Event
	last_time := sdl.GetTicks()

	running := true
	for running {
		current_time := sdl.GetTicks()
		delta_time := (current_time - last_time) / 1000.0
		last_time = current_time

		sdl.SetRenderDrawColor(game.renderer, 0, 0, 0, 255)
		sdl.RenderClear(game.renderer)
	}
}
