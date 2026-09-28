package main

import "core:os"

CLI_State :: enum {
	RUN,
	HELP,
	ERROR
}

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

parse_args :: proc(config: ^Config, args: []string) -> CLI_State {
	config_default(config)
}
