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

- **Player.** Movement, firing, bullets, and bullet/bacteria collision. Only
  Neutral ammo exists in code: `current_ammo` is set at init and never changed;
  there is no switching control. Weapon weakness is gone: `WeaponDefinition`
  carries a single `damage` value. Neutral, PCN, and PMX are all `damage = 3`
  placeholders until Phase 7 tuning.
- **Bacteria.** Species definitions for Strep, Staph, E. coli, and Pseudomonas;
  a flat cold/hot SoA pool owned by the level; spawning, movement, diving, and
  rendering. All four species enter, hold, dive, and return. The non-Strep
  entry/hold/dive/return code is duplicated placeholder behavior until each
  species gets bespoke motion in Phase 6. Each bacterium stores its owning wave
  index, with `-1` meaning not in play; the slot is cleared at death.
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
  sets `level_end` and hands off to the level transition.
- **Procedural generation.** Seed derivation, entry-point selection, formation
  bounds, line formation layout, and entry paths. Entry is pinned to top-center
  for levels 1–2.
- **Flee threshold.** Rolled once per wave from the wave seed, held as
  per-mille destroyed, shown in the debug overlay as the base value, and consumed
  by the crossing test. The test uses
  `clamp(base + 50 * max_buff_count, 500, 1000)`, recomputed from the wave's
  active owners on each check. `Level.flee_prohibited` skips the draw and uses
  `1000`.
- **Flee phase.** Crossing marks every remaining owned bacterium `.Fleeing` and
  sets `flee_phase_active`. The phase is zero-duration in 1.3: finish runs on the
  same frame, pushes each survivor into the roster with
  `waves_until_return = 1`, clears ownership, deactivates the slot, and
  increments `fled_count`. Advancement waits for the phase. Fleeing bacteria
  remain targetable, so a phase kill counts as destroyed and produces no roster
  entry; this is unreachable until the animation gives the phase duration.
  `flee begin` and `flee finish` logs include candidate and fled counts and the
  elapsed phase time.
- **Resistance buffs.** `BuffCategory` is ordered Hardy, Resistant, Biofilm,
  and Frenzied, frozen because it indexes the seeded roll. A buff is a
  `BuffInstance` (category plus a rolled permille fraction of the category
  ceiling from `BUFF_DEFS`); up to five are stored per bacterium and on roster
  entries. The fraction is drawn from the 5-level block bands. `buff_total`
  converts each slot and caps the sum at the category ceiling.
  - Hardy raises `max_health` at spawn.
  - Frenzied raises `speed` at spawn; it currently affects only Strep entry and
    dive motion.
  - Resistant reduces incoming damage, floored at 1, at the damage site.
  - Biofilm absorbs a capped number of hits, reset on spawn.
  `wave_flee_begin` rolls one category and fraction per escaping bacterium from
  `derive_seed(wave.seed, .Buff, slot_index)`; `wave_flee_finish` copies the
  result into the roster entry.
- **Species variety.** Fresh spawns draw a species from
  `derive_seed(wave.seed, .Wave, 1 + spawn_index)` against
  `min(species_unlocked, len(BACTERIA_DEFS))`. Level 1 draws Strep only; Staph,
  E. coli, and Pseudomonas unlock every five levels. Returners keep their stored
  species.
- **Return roster.** `PendingBacteria` stores a species, buffs, and
  `waves_until_return`; `ReturnRoster` on `World` is a compact FIFO capped at
  `MAX_ENEMIES`, with the oldest entry at index 0. `world_init` initializes it
  and `level_init` cannot clear it. Fled bacteria enter with delay one, and
  `return_roster_tick` decrements every positive delay when a wave completes, so
  an entry is due for the next wave. Due entries are consumed at spawn time
  before fresh bacteria, each taking one of the wave's existing slots with its
  species, buffs, and restored health preserved; overflow stays queued and a
  full roster drops the oldest. Return, roster push/drop, and flee-prohibited
  logs report the flow.
- **Level transition.** When the last wave resolves, `.Playing` sees
  `level_end` and switches to `.Level_Transition`. A `LevelTransition`
  accumulator on `World` (temporary five-second duration) holds the frozen world
  frame, dims it with a blended black overlay that fades in over the first 10%
  of the hold, and draws `Level N Cleared` / `Wait for next level`. On expiry the
  transition is the only caller of `level_init` for later levels, passing
  `master_seed` and `level_number + 1`; it clears bullets and returns to
  `.Playing`. The player keeps its position, and the return roster survives.
  `Level.end_chance` is removed. `transition start` and `transition end` logs
  report the handoff.
- **App shell.** Menu, playing, level-transition, and paused states; Esc pauses;
  `--debug` skips the menu. `Game_Over` exists but is unreachable until Phase 5B
  adds player health.
- **CLI.** `--debug`, `--seed`, `--level`, `--no-vsync`, and `--help`.
  `--no-vsync` is parsed but not read; the renderer always enables vsync.
- **Debug overlay.** FPS, game state, wave count, and the active wave's flee
  threshold, drawn directly with SDL.

Not yet implemented:

- Fleeing animation.
- Player health, contact and hazard damage, invulnerability, game over, and the
  health bar (Phase 5B).
- Scrolling layered 32×32 panel background (Phase 3B).
- Branding, logo, palette, typography, and presentation assets (Phase 12).
- Clostridium and Klebsiella, the first Phase 6 roster expansion.
- Per-species entry, hold, dive, and return behavior; the current non-Strep paths
  are placeholders (Phase 6). Frenzied does not yet affect their dive speeds.
- Weapon switching and unlocks (Phase 7).
- Clay UI, settings, skill tree, bosses, and adaptive wave composition. The skill
  tree will replace the temporary timed transition hold.
- A working no-vsync path and frame limiter.
- Unit tests.
- Cross-platform release packaging.

## Important Principles

- Deterministic generation
- Simple systems
- Minimal dependencies
- Explicit data flow
