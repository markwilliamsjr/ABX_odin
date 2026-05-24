package main

import sld "vendor:sdl2"

Level :: struct {
	wave:              [MAX_WAVES]Wave,
	wave_count, level: int,
}

Wave :: struct {}
