package main

Config :: struct {
	debug, no_vsync, has_seed: bool,
	level:                     int,
	seed:                      u64,
}

config_default :: proc(config: ^Config) {
	config.debug = false
	config.no_vsync = false
	config.level = 1
	config.has_seed = false
}
