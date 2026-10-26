# Current Session

## Date

2026-10-26 (implementation; planning 2026-10-24)

## Goal

Finish the Level and Wave Lifecycle slice: the enemy count model, early-level
variance, pinned entries, and the `wave_index` authority. Clay UI and release
packaging are deliberately deferred.

## What was worked on

Implemented Units A–D plus the `wave_index` field:

- **A.** `WaveParams.total_enemies` → `enemy_budget`, `Wave.total_enemies` →
  `enemy_count`, and `wave_init` takes `enemy_count` explicitly.
- **B.** `level_init` loops over every drawn wave, deriving `.Wave, i` per index,
  with wave 0 coming from the same loop.
- **C.** The level budget is split across waves (base + remainder, floor 3, floor
  wins), a per-wave ±1 jitter is drawn from `derive_seed(wave_seed, .Wave, 0)`, and
  block 0's wave count draws `[1, min(level, 4)]`.
- **D.** Entries are pinned to `ENTRY_POINTS[2:3]` for levels 1–2.
- `wave_index` added to `Level`, initialized to 0. `Wave.is_active` removed:
  `wave_index` is now the only authority for the active wave.

`odin check src` is clean. Runtime verification numbers are still not recorded.

## What was decided

The count-model decisions are recorded under 2026-10-24 in `DECISIONS.md`:
"Enemy counts" and "Early-level determinism".

This session added two implementation decisions:

- **`wave_index` is the sole authority.** `is_active` was removed rather than
  redefined; no code read it.
- **Clay becomes the UI layer, deferred.** The overlay, menu, settings, and later
  the skill tree will be built on Clay, vendored at `src/clay-odin/` and compiled
  locally. Development stays Linux-only; releases will be built natively on each
  OS in CI. The full task list lives in `ROADMAP.org` under Deferred, "Clay UI
  Foundation" and "Cross-Platform Release".

**Degenerate ranges skip the draw.** `rand.int_range` panics unless `lo < hi`, so
the level-1 wave count, the band-0 jitter, and the `MAX_WAVES` saturation return
their single value without drawing. This supersedes the earlier claim that such
draws still consume their seed triple. Harmless: every draw site owns a
throwaway RNG.

## Known issues in the current code

These are open and need fixing before `wave_index` can advance:

- **Inverted wave guard.** `world_update` has
  `if level.wave_index >= level.wave_count { wave_update(...) }`. It should be
  `<`, and `wave_dive_update` has no guard at all. As written, wave updates are
  skipped while the index is valid and index out of bounds once it is not.
- **Overlay threshold reads two waves.** In `debug.odin`, the cache condition
  reads `wave[wave_index]` but the formatted text and the cache assignment still
  read `wave[0]`. There is also no bounds guard. Moot once the overlay moves to
  Clay, but wrong today.
- **`int_range` semantics.** `rand.int_range` is `[lo, hi)`, so the current wave
  counts and jitter are one short of the documented ranges. Parked in
  `ROADMAP.org` under "Parked: Range Semantics and Unit Tests"; do not write
  tests against the current behaviour before deciding.

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

## Current task

The lifecycle slice is nearly complete; Wave Resolution is the remaining core.
The overlay portion is deferred to Clay and should not hold up the slice.

## Next step

Decide wave membership tracking before writing resolution logic. The current
`enemy_indices` array can contain duplicate slot indices within one wave, because
`find_free_bacteria_slot` recycles slots when bacteria die before later spawns.
Counting resolved bacteria from that array is therefore unsound today.

Options are to give each bacterium its owning wave identity (for example
`wave_index` plus level number on `BacteriaHot`) so kills can be attributed at the
moment `active` flips, or to introduce a separate membership structure. Then:
destroyed counter, crossing test, resolved counter, wave completion, and finally
advancing `wave_index`.

## Verification to record

Not yet recorded. The expected values:

- level 1: one wave, 5 enemies, no jitter, top-center entry across seeds
- level 20: shares sum to 43
- level 26: 10 waves, shares sum to 55, no `int_range` panic
- level 6+: adjacent shares may differ by 2
- same seed twice: identical shares
- seed-collision check across a level's waves (now unblocked)

## Previously completed (2026-10-21 to 2026-10-24)

State and Input, CLI flags, and the planning of the count model. See
`ROADMAP.org` under Completed, and `DECISIONS.md` for the recorded decisions.
