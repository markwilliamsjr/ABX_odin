# Current Session

## Date

2026-10-31 (last implementation 2026-10-26; planning 2026-10-24)

## Goal

Finish the Level and Wave Lifecycle slice: wave resolution, fleeing and
returning, resistance buffs, and real level transition. Clay UI and release
packaging stay deferred.

## What was worked on

The 2026-10-26 implementation session completed Units A–D plus the `wave_index`
field:

- **A.** `WaveParams.total_enemies` → `enemy_budget`, `Wave.total_enemies` →
  `enemy_count`, and `wave_init` takes `enemy_count` explicitly.
- **B.** `level_init` loops over every drawn wave, deriving `.Wave, i` per index,
  with wave 0 coming from the same loop.
- **C.** The level budget is split across waves (base + remainder, floor 3, floor
  wins), a per-wave ±1 jitter is drawn from `derive_seed(wave_seed, .Wave, 0)`,
  and block 0's wave count draws `[1, min(level, 4)]`.
- **D.** Entries are pinned to `ENTRY_POINTS[2:3]` for levels 1–2.
- `wave_index` added to `Level`, initialized to 0. `Wave.is_active` removed:
  `wave_index` is now the only authority for the active wave.

The 2026-10-31 session restructured the docs only: `ROADMAP.org` now lists
remaining work; rationale moved to `DECISIONS.md`, intended design to
`ARCHITECTURE.md`, and current state to `PROJECT.md`. No source files changed.

## Current code state

`odin check src` was clean at the end of the implementation session. Runtime
verification numbers are still not recorded.

Two issues recorded in earlier sessions are fixed in the current source: the
wave guard uses `<` and `wave_dive_update` is guarded, and the overlay
consistently reads `wave[wave_index]`.

## Current task

Wave Resolution. Nothing currently detects that a wave has finished.

## Next step

Decide wave membership tracking before writing resolution logic. The current
`enemy_indices` array can contain duplicate slot indices within one wave,
because `find_free_bacteria_slot` recycles slots when bacteria die before later
spawns. Counting resolved bacteria from that array is therefore unsound today.

Options are to give each bacterium its owning wave identity (for example
`wave_index` plus level number on `BacteriaHot`) so kills can be attributed at
the moment `active` flips, or to introduce a separate membership structure. Then:
destroyed counter, crossing test, resolved counter, wave completion, and finally
advancing `wave_index`.

## Open issues

- `rand.int_range` is `[lo, hi)`, so wave counts and jitter are one short of the
  documented ranges. Decide inclusive vs exclusive before writing tests. See
  `DECISIONS.md` "Early-level determinism".
- `Level.end_chance` and `Level.level_end` are unread. `end_chance` is
  superseded by the rolled flee threshold.
- `threshold_picker`'s spread draws `[-50, 49]`, not symmetric ±50.
- `--no-vsync` is parsed but never read; the renderer always enables vsync.
- `species_unlocked` is computed but never read; `bacteria_spawn` hardcodes
  `.Strep`.
- Decisions still read wall-clock time: `formation_complete_time`, the dive
  gate, and `delta_time`.

## Verification to record

Not yet recorded. The expected values:

- level 1: one wave, 5 enemies, no jitter, top-center entry across seeds
- level 20: shares sum to 43
- level 26: 10 waves, shares sum to 55, no `int_range` panic
- level 6+: adjacent shares may differ by 2
- same seed twice: identical shares
- seed-collision check across a level's waves
- once resolution exists: same seed twice gives identical wave composition,
  formations, flee thresholds, and return schedules

## Problems discovered earlier

- **Loop before the draw.** The wave loop was placed above the
  `wave_count_picker` call, so `wave_count` was still 0 and the loop never ran.
- **Split's else branch.** `share = 0` instead of `base` made every wave past the
  remainder exactly the floor.
- **Jitter band inverted.** Block 0 took band 1 and later blocks took band 0.
- **Swapped call arguments.** `level_number` and `enemy_budget` were passed in
  each other's positions. Both are `int`, so it compiled silently.
- **`int_range` assertion.** Level 1 crashed at startup: `int_range(1, 1)`.
  Guarding that exposed the band-0 jitter and the `MAX_WAVES` saturation.
- `fmt.println("%v", x)` does not format; `fmt.printfln` does.

## Previously completed (2026-10-21 to 2026-10-24)

State and Input, CLI flags, and the planning of the count model. See
`PROJECT.md` Current State and `DECISIONS.md` for the recorded decisions.
