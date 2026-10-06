# Current Session

## Date

2026-10-03 to 2026-10-06

## Goal

Design level advancement and the fleeing-bacteria difficulty system, and record
the decisions. No implementation written — this session was planning and
documentation only.

## What was worked on

Reviewed the project documentation, then assessed the code against it. Found
that `ARCHITECTURE.md` describes a game substantially further along than the
source actually is, and worked through the design for the next slice: level
advancement, wave sequencing, fleeing bacteria, and what "stronger" means.

Then worked through determinism, the strengthening model, and return scope,
recording each as it was settled.

## What was decided

**Documentation conventions.** `ARCHITECTURE.md` describes intent;
`PROJECT.md` describes current state. Gaps between the docs and the code are the
unfinished state of an already-documented design, not contradictions.

**Game structure.** A level is a sequence of waves. Some levels have one wave,
some have more. A wave ends when every bacterium in it is resolved — destroyed,
fled, or still alive.

**Level composition.** Wave count per level is a seeded random draw, range
growing with level.

**Fleeing.** Triggered when remaining bacteria cross a threshold drawn once per
wave at spawn and compared deterministically thereafter. No per-frame probability
anywhere in the flee path.

**Strengthening is resistance only.** Bacteria never change species. A fleeing
bacterium withdraws and returns having developed resistance. Four categories:
Hardy, Resistant, Biofilm, Frenzied. Each escape grants one category and restores
spawn max health. Five buff slots, per-instance on `BacteriaCold`, magnitudes in
a separate `BUFF_DEFS` table.

**Return queue.** Survives level transitions — it lives on `World`. Bacteria
enter the *next wave* positionally, so a level never opens with the whole
backlog. Carried bacteria may flee again; there is no escape counter.

**Bosses flush.** At a boss level all bacteria must be destroyed; fleeing is not
permitted. This bounds the resistance system and removes the need for a
sixth-escape rule. Boss specifics deferred.

**Determinism** means deterministic decisions with continuous motion — reading C.
A tick counter drives every decision; real elapsed time only moves things. No
decision may read wall-clock time. Recorded input replay explicitly out of scope.

**Scope.** The next slice is level advancement plus a minimal menu, so the
feature is runnable when it lands. The skill tree waits until advancement, procgen,
and formation gen are solid.

**Seeding.** Added `.Level` to `SeedCategory`. Seeds chain rather than counting
globally: `level_seed = derive_seed(run_seed, .Level, level_number)`, then
`wave_seed = derive_seed(level_seed, .Wave, wave_index)`. The uniqueness invariant
is per `(parent, category, number)` triple. A global monotonic wave number was
considered and rejected — it needs cumulative state threaded through level
transition, and numbering level 9's waves requires already knowing how many waves
earlier levels drew.

## Problems discovered

- `level_init` (`src/level.odin:103`) hardcodes `level_to_params(1)`; `Level.level`
  is never written. The scaling curve exists but has only ever run at level 1.
- `Level.wave` is `[10]Wave` but `src/game.odin:446-447` hardcodes `wave[0]`.
  Waves 1-9 unused.
- `world.state` is set to `.Menu` and never changed, and **the main loop ignores
  `world.state` entirely** — every system updates unconditionally. No state gating
  exists, so the game cannot currently be started.
- `GameState.Level_Transition`, `Level.level_end`, and `Level.end_chance` are all
  declared and never used.
- `Level.wave_count` is never written, but the debug overlay renders it — it
  displays `0` permanently.
- Nothing detects that a wave has finished. `wave_update` tracks
  `formation_complete` but no completion predicate exists.
- `src/level.odin:157` — `if u64(sdl.GetTicks()) >= wave.formation_complete_time`
  is **always true**. The dive gate has never gated anything, leaving
  `formation_complete_time` dead.
- `formation_complete` (`src/level.odin:136-148`) is a decision derived from
  continuous motion, which violates the determinism rule.
- `species_unlocked` (`src/procedural.odin:124`) is computed and never read;
  `bacteria_spawn` hardcodes `.Strep` (`src/level.odin:128`). The game is one
  species throughout.
- **Wave membership cannot be tracked by index.** `wave.enemy_indices` indexes the
  flat `bacteria.cold[]` pool, and slots are recycled by `find_free_bacteria_slot`.
  Once bacteria leave and return, one can land in a recycled slot and be counted
  as resolved for the wrong wave.
- `derive_seed(seed, .Wave, 0)` passes a hardcoded `0`, so different levels get
  identical wave seeds. Fixed by chaining, not by a global wave counter.
- `parse_args` (`src/cli.odin:24`) declares return type `CLI_State` with no
  terminating return. Looks like a compile error, or the file is not in the build.
  `Config.seed` and `Config.level` are never populated; only `--debug` is handled.
- Root-level `abx_notes.org` is a self-referential symlink loop, untracked and
  gitignored. Agreed it can go; not yet removed.

## Current task

Design complete for the level advancement slice. Nothing implemented.

Docs updated: `ARCHITECTURE.md` rewritten to match the settled design;
`DECISIONS.md` filled in (was empty); `ROADMAP.org` populated (was an empty
heading); plan written to `~/.opencode/plan/level-advancement.md` with 8 tasks
in dependency order.

Follow-up: seeding settled on chaining (see Decisions → Seeding), with the
per-wave flee threshold drawn from `wave_seed` rather than the level seed. Plan
written to `~/.opencode/plan/seed-chaining.md`.

## Next step

**Decide the flee threshold direction.** `WaveParams.threshold = 0.8`
(`src/procedural.odin:127`) is ambiguous between fraction destroyed and fraction
remaining. Read as fraction remaining, 0.8 means bacteria flee while 80% are
still alive, inverting the intended difficulty. This blocks Task 4 (wave
resolution) and is the only open question that blocks implementation.

Everything else open is tuning (buff-threshold scaling, Frenzied capping,
Resistant vs. weapon weakness), deferred boss specifics, or cosmetic (buff
visuals).