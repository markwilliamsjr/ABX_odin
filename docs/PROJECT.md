# ABX!

## What is it?

ABX! is a 2D action game written in Odin using SDL2.

The player is an antibiotic that is fighting waves upon waves of bacteria. 

## Goal

Create fun, deterministic enemy waves.

The same seed should produce the same
results every time.

## Technology

- Odin
- SDL2
- Linux

## Current State

**This section describes what exists today.** The intended design lives in
`ARCHITECTURE.md`; a gap between the two is unfinished work, not a
contradiction.

Implemented:

- **Player.** Movement, weapon selection, firing, bullets, and bullet/bacteria
  collision.
- **Bacteria.** Species definitions for Strep, Staph, E. coli, and Pseudomonas;
  a flat cold/hot SoA pool owned by the level; spawning, movement, diving, and
  rendering. Each bacterium stores its owning wave index, with `-1` meaning not
  in play; the slot is cleared at death.
- **Levels and waves.** Seeded level and wave seeds; per-level wave count; the
  `3 + level*2` enemy budget split across waves with a floor of 3; per-wave
  count jitter; `wave_index`; all drawn waves initialized at level start. Each
  wave stores its own index, and the formation, diver-count, and diver-selection
  scans find members by ownership rather than by a slot list.
- **Wave accounting.** `destroyed_count` and `fled_count` per wave, attributed
  at the moment of death; `resolved` is their sum. Spawning reports
  `spawn_finished` when the budget is filled or the regions run out, so a
  shortfall wave still forms up rather than stalling.
- **Wave resolution.** The threshold test runs once spawning has finished, sets
  `threshold_crossed`, and removes nothing yet. A wave completes when everything
  that spawned has left play; `wave_index` then advances once, and the last wave
  sets `level_end`. The transition itself is still 1.5.
- **Procedural generation.** Seed derivation, entry-point selection, formation
  bounds, line formation layout, and entry paths. Entry is pinned to top-center
  for levels 1–2.
- **Flee threshold.** Rolled once per wave from the wave seed, held as
  per-mille destroyed, shown in the debug overlay, and consumed by the crossing
  test. The flee response is not implemented.
- **Resistance buff scaffolding.** `BuffCategory` covers Hardy, Resistant,
  Biofilm, and Frenzied. A five-slot buff list and `buff_count` live on
  `BacteriaCold`; `BUFF_DEFS` holds magnitudes; `max_health` lives on
  `BacteriaHot`; and `bacteria_buff_add` replaces the oldest slot when full. No
  buff is rolled or applied yet.
- **App shell.** Menu, playing, and paused states; Esc pauses; `--debug` skips
  the menu. `Level_Transition` and `Game_Over` exist but do nothing.
- **CLI.** `--debug`, `--seed`, `--level`, `--no-vsync`, and `--help`.
  `--no-vsync` is parsed but not read; the renderer always enables vsync.
- **Debug overlay.** FPS, game state, wave count, and the active wave's flee
  threshold, drawn directly with SDL.

Not yet implemented:

- Fleeing, returning bacteria, the pending roster, and resistance buff effects.
- Real `Level_Transition` logic.
- Clay UI, settings, skill tree, bosses, and adaptive wave composition.
- A working no-vsync path and frame limiter.
- Unit tests.
- Cross-platform release packaging.

## Important Principles

- Deterministic generation
- Simple systems
- Minimal dependencies
- Explicit data flow
