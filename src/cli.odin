package main

import "core:fmt"
import "core:os"

CLI_State :: enum {
	RUN,
	HELP,
	ERROR,
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
	index := 1
	for index < len(args) {
		if args[index] == "--debug" {
			config.debug = true
			index += 1
		} else {
			fmt.printf("WRONG")
			return .ERROR
		}
	}
	return .RUN
}

useage :: proc() {
	fmt.println("ABX!")
	fmt.println("")
	fmt.println("Useage: abx [args]")
	fmt.println("Optional Usage: odin run src -- [args]")
	fmt.println("")
	fmt.println("  --debug         Shows the debug overlay on start")
	fmt.println("  --no-vsync      Start with vsync disabled")
	fmt.println("  --seed <n>      Use a fixed seed, instead of a random one")
	fmt.println("  --level <n>     Start at level <n>")
	fmt.println("  -h, --help      Show help menu")
	fmt.println("")
	fmt.println("The active seed is printed at startup. Reproduce a run by")
	fmt.println("passing it back with --seed.")
}
