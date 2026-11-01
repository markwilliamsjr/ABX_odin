# Current Session

## Date

2026-11-01 (ownership slice; earlier implementation and decisions 2026-10-31)

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
  and block 0's wave count was specified as `[1, min(level, 4)]` — the draw only
  reached that upper bound once 1.1 added the `+1`.
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

Only `DECISIONS.md` and this session file changed in the decision pass; no
source files were touched then.

Roadmap 1.1 was then implemented in `src/level.odin` and committed as
`93405b0`:

- count jitter draws `(-band, band + 1)`; band 0 still skips the draw
- block 0 draws `int_range(1, min(level, 4) + 1)`, with the level-1 shortcut
  retained
- the `MAX_WAVES` branch triggers on `max >= MAX_WAVES` so block 3 joins the
  clamped path, and draws `int_range(min, MAX_WAVES + 1)`
- block 5+ still returns `MAX_WAVES` without drawing
- the threshold spread draws `(-50, 51)` with no adjustment on the result

The 2026-11-01 session implemented the ownership slice of 1.2:

- `Bacteria` moved from `World` to `Level`; `level_init` now takes only
  `(&level, master_seed, level_number)`.
- `Wave.index` stores the wave's position; assigned in `wave_init`, which gained
  a `wave_index` parameter.
- `BacteriaCold.wave_index` stores the owner, with `OWNER_NONE :: -1`. Set in
  `bacteria_init` from a new `BacteriaSpawnParams.wave_index`, and cleared
  together with `hot.active = false` at the health-zero branch in
  `collision_update`.
- `bacteria_pool_reset` zeroes the pool and then writes the sentinel into every
  ownership slot; `level_init` calls it first.
- The formation check, diver count, and `select_first_found` now scan the pool
  by ownership; `Wave.enemy_indices` is deleted.
- A failed `bacteria_spawn` returns before advancing `spawn_index` or
  `spawn_count`, so it is retried on the next spawn tick.
- The formation check counts owned bacteria and requires
  `owned == spawn_count`, so a wave whose members all died is not vacuously
  "holding".

Diving did not work after the first pass: both new owner scans had the skip test
inverted (`==` instead of `!=`), so `select_first_found` rejected the wave's own
bacteria and returned `-1`. Fixing both restored diving.

## Current code state

`odin check src` is clean with 1.1 and the ownership slice in place. The
ownership decision is implemented; counters, crossing, completion, and
advancement are not. Runtime verification numbers are still not recorded.

Two issues recorded in earlier sessions are fixed in the current source: the
wave guard uses `<` and `wave_dive_update` is guarded, and the overlay
consistently reads `wave[wave_index]`.

## Current task

Roadmap 1.2, counters and death attribution. Ownership exists, but nothing
detects that a wave has finished; `wave_index` is still pinned at 0.

## Next step

Land the counters without any transition logic, so the numbers can be observed
in isolation:

- add `destroyed_count` and `fled_count` to `Wave`, plus a `resolved` helper
  returning their sum
- pass the owning wave (or the `Level`) into `collision_update` and increment
  `destroyed_count` in the branch that already clears `active` and the owner
- log the increment; a five-enemy wave should log five destructions and reach
  `resolved == spawn_count` with `wave_index` unchanged

Crossing, completion, and advancement follow as separate steps. Keep the
`wave_init` reset of counters, timers, and flags with the crossing step, since
`level_init` currently re-runs `wave_init` over every wave it will use and that
masks a missing reset rather than proving one.

The formation check is the one scan that is not fully behaviour-neutral: it
used to walk `0..<spawn_count` over `enemy_indices`, including dead and recycled
slots. It now walks the live pool. "The game plays the same" therefore does not
verify it.

## Open issues

- `Level.end_chance` and `Level.level_end` are unread. `end_chance` is
  superseded by the rolled flee threshold.
- `--no-vsync` is parsed but never read; the renderer always enables vsync.
- `species_unlocked` is computed but never read; `bacteria_spawn` hardcodes
  `.Strep`.
- Decisions still read wall-clock time: `formation_complete_time`, the dive
  gate, and `delta_time`.
- `wave_init` does not reset `spawn_count`, `spawn_index`, timers, or the
  formation and crossing flags. It only works because `level_init` re-inits
  every wave it will use.
- The spawn-region walk in `wave_update` is unbounded: if `generate_formation`
  places fewer than `enemy_count`, it can index past `MAX_REGIONS`.
- The debug overlay reads `wave[wave_index]` unconditionally; once advancement
  can set `wave_index == wave_count`, it will read an uninitialised wave.

## Verification to record

Ownership slice: diving works after the inverted owner scans were fixed. Still
to record are the checks that separate "it runs" from "ownership is correct":

- exactly one bacterium dives at a time (`max_simult_divers = 1`), and the next
  is selected only after the previous one leaves play
- with `--level 2`, wave 1's bacteria are never selected by wave 0's dive pass
- killing bacteria mid-formation does not resurrect the freed slots as divers
- same seed twice: identical formation and dive order

1.1, still unrecorded. The first observations are the ones the old exclusive
ranges hid: levels 2–5 can now draw their full upper wave counts, block 1 waves
can reach 6, block 2 8, and block 3 10. Expected values assume the inclusive
range semantics settled on 2026-10-31:

- level 1: one wave, 5 enemies, no jitter, top-center entry across seeds
- levels 2–5 across seeds: 2, 3, and 4 waves respectively can appear
- level 6+: adjacent shares may differ by 2
- level 20: shares sum to 43, 10 waves can appear
- level 26: 10 waves, shares sum to 55, no `int_range` panic
- same seed twice: identical shares
- seed-collision check across a level's waves
- once resolution exists: same seed twice gives identical wave composition,
  formations, flee thresholds, and return schedules

## Problems discovered in the ownership slice

- **Inverted skip tests.** Converting `enemy_indices` loops into owner scans
  flipped the guard in two places: `if ... == wave.index do continue` instead of
  `!=`. The selector skipped exactly the wave's own bacteria and returned `-1`,
  so nothing dived; the diver count skipped its own divers, so the cap was never
  reached. The second was masked by the first. Owner scans are `!=` skip tests;
  a scan that "finds nothing" is the symptom to expect when one is inverted.
- **Vacuous formation completion.** An owner scan ignores dead bacteria, so a
  wave whose members had all died would satisfy "all holding" with an empty set.
  The `owned == spawn_count` term is what keeps the check honest; without it the
  formation completes over nothing.

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
