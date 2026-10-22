package main

import "core:fmt"
import "core:os"
import "core:strconv"

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
	config.seed = 1
}

parse_args :: proc(config: ^Config, args: []string) -> CLI_State {
	config_default(config)
	index := 1
	for index < len(args) {
		if args[index] == "--debug" {
			config.debug = true
			index += 1
		} else if args[index] == "--seed" {
			if (index + 1) >= len(args) {
				return .ERROR
			}
			seed, ok := strconv.parse_u64(args[index + 1])
			if !ok {
				fmt.eprintfln("Invalid value. Must be a number and must be 0 or greater")
				return .ERROR
			}
			if seed < 1 {
				fmt.eprintfln("Number must be 0 or greater")
				return .ERROR
			}
			config.has_seed = true
			config.seed = seed
			index += 2
		} else if args[index] == "--level" {
			if (index + 1) >= len(args) {
				return .ERROR
			}
			level, ok := strconv.parse_int(args[index + 1])
			if !ok {
				fmt.eprintfln("Invalid value. Must be a number and must be 1 or greater")
				return .ERROR
			}
			if level < 1 {
				fmt.eprintfln("Number must be 1 or greater")
				return .ERROR
			}
			config.level = level
			index += 2
		} else if args[index] == "--no-vsync" {
			config.no_vsync = true
			index += 1
		} else if args[index] == "-h" || args[index] == "--help" {
			return .HELP
		} else {
			fmt.eprintfln("Command not found, --help for commands")
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
	fmt.println("  --no-vsync      Start with vsync disabled - simulation runs faster")
	fmt.println("  --seed <n>      Use a fixed seed, instead of a random one")
	fmt.println("  --level <n>     Start at level <n> - default <1>")
	fmt.println("  -h, --help      Show help menu")
	fmt.println("")
	fmt.println("The active seed is printed at startup. Reproduce a run by")
	fmt.println("passing it back with --seed.")
}
