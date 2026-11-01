# Current Session

## Date

2026-10-31 (last implementation 2026-10-26; decisions 2026-10-31)

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

The same day's decision session settled two more questions without changing
source:

- **Range semantics** are inclusive: every draw passes `hi + 1`. The documented
  ranges are the source of truth; the exclusive upper bound is an API detail.
- **Wave membership**: the `Bacteria` pool moves into `Level`, each `Wave` gets
  a stored index, and each bacterium stores its owning wave index with `-1` as
  the not-in-play sentinel. Ownership is an independent invariant, and
  `level_init` zeroes the pool and then writes the sentinel into every slot.

Only `DECISIONS.md` and this session file changed; no source files were touched.

## Current code state

`odin check src` was clean at the end of the implementation session. Runtime
verification numbers are still not recorded. The range and ownership decisions
are not implemented yet.

Two issues recorded in earlier sessions are fixed in the current source: the
wave guard uses `<` and `wave_dive_update` is guarded, and the overlay
consistently reads `wave[wave_index]`.

## Current task

Wave Resolution. The membership model is decided but not implemented; nothing
currently detects that a wave has finished.

## Next step

Implement 1.1 first: pass `hi + 1` at the four draw sites, clamp `MAX_WAVES`
before the `+1`, and leave the documented table unchanged. Then begin 1.2 with
ownership as a behaviour-neutral step: move `Bacteria` into `Level`, store the
index on `Wave`, store the owning index on `BacteriaCold`, clear it on death and
flee, replace the `enemy_indices` scans, and delete the array. Counters,
crossing, completion, and advancement follow as separate steps.

## Open issues

- `Level.end_chance` and `Level.level_end` are unread. `end_chance` is
  superseded by the rolled flee threshold.
- `--no-vsync` is parsed but never read; the renderer always enables vsync.
- `species_unlocked` is computed but never read; `bacteria_spawn` hardcodes
  `.Strep`.
- Decisions still read wall-clock time: `formation_complete_time`, the dive
  gate, and `delta_time`.
- A zeroed `BacteriaCold` is not a valid "not in play" state, because `0` is a
  valid wave index. The `level_init` reset must include the `-1` sentinel pass.
- The spawn-region walk in `wave_update` is unbounded: if `generate_formation`
  places fewer than `enemy_count`, it can index past `MAX_REGIONS`.
- The debug overlay reads `wave[wave_index]` unconditionally; once advancement
  can set `wave_index == wave_count`, it will read an uninitialised wave.

## Verification to record

Not yet recorded. The expected values assume the inclusive range semantics
settled on 2026-10-31:

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
