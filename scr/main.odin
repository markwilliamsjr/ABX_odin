package main

import "core:os"
import "core:fmt"
import "vender:sdl2"

SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 360

GameStateMode :: enum {
    STATE_MENU,
    STATE_PLAYING,
    STATE_LEVEL_TRANSITION,
    STATE_PAUSED,
    STATE_GAME_OVER
}

main :: proc() {
    result := 0
    gameStarted := false
    window := SDL_CreateWindow("ABX!", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 
        SCREEN_WIDTH, SCREEN_HEIGHT, WINDOW_BORDERLESS)
    
    if window == nil {
        fmt.eprintf("Window could not be created. SDL_Error: %s\n", SDL_GetError())
        result = 1
        cleanUp()
    }

    renderer := SDL_CreateRenderer(
        window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC
    )

    if renderer == nil {
        fmt.eprintf("Renderer could not be created. SDL_Erro: %s\n", SDL_Error())
        result = 1
        cleanUp()
    }
}

cleanUp :: proc() {
    if renderer do SDL_DestroyRenderer(renderer)
    if window do SDL_DestroyWindow(window)
    SDL_Quit()
}