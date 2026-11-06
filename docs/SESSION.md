# Current Session

## Date

2026-11-06 (1.3 design settled; 1.2 complete 2026-11-05; earlier work 2026-11-01
and 2026-10-31)

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

The counters and spawn-bound slice followed, committed as `b2c7ca5`:

- `destroyed_count` and `fled_count` on `Wave`, with `wave_resolved` returning
  their sum. No stored `resolved` field.
- `collision_update` takes `^Level`. A kill captures `cold.wave_index` before
  clearing `active` and the owner, bound-checks the owner against `wave_count`,
  and increments the owning wave. A per-kill log line is in place.
- `wave_init` now owns its reset: `spawn_count`, `spawn_index`, `spawn_region`,
  `spawn_timer`, `dive_timer`, `formation_complete_time`, `destroyed_count`,
  `fled_count`, `threshold_crossed`, `formation_complete`, `spawn_finished`.
  `level_init` zeroes `level.wave` before the wave loop and sets
  `level_end = false`.
- `spawn_finished` separates "spawning is done" from "the budget was filled".
  It is set when `spawn_count == enemy_count` or when the region walk runs out
  of regions. `Wave.region_count` stores the bound the walk was missing.
- The formation check gates on `spawn_finished` rather than on
  `spawn_count == enemy_count`, so a shortfall wave can still form up.

The first attempt at the spawn bound was inert: `wave_init` never stored
`region_count`, and the exhaustion test used `>` where the walk guarantees
`==`. The two bugs masked each other and only showed on the shortfall path.

The rest of 1.2 landed in `6d0d9ff` and `f7930ed`:

- `wave_update` applies `destroyed_count * 1000 >= spawn_count *
  threshold_permille` once `spawn_finished` and `spawn_count > 0`, sets
  `threshold_crossed` once, and logs the transition. Crossing removes nothing;
  `fled_count` stays zero.
- `wave_resolution_update(level)` runs after the dive update and inside the
  `wave_index < wave_count` guard. It completes the wave when `spawn_finished`,
  `spawn_count > 0`, and `wave_resolved == spawn_count`, advances `wave_index`
  once, and sets `level_end` when the new index reaches `wave_count`.
- The pass logs resolution, advancement, and level end.
- `debug.odin` clamps the displayed wave with
  `min(wave_index, wave_count - 1)`, so the overlay keeps reading a valid wave
  after the level ends.
- The completion gate uses `spawn_finished`, not `spawn_count == enemy_count`,
  so a shortfall wave crosses and completes against what actually spawned.
  `DECISIONS.md` was amended to match.

## 1.3 design decisions (2026-11-06)

No source changed in this pass; these decisions are recorded in `DECISIONS.md`.

- Flee threshold scales with the wave's highest buff count:
  `clamp(base + 50 * max_buff_count, 500, 1000)`, recomputed at the crossing test.
- Returning bacteria substitute into the next wave's existing spawn slots, FIFO,
  returners first, overflow stays queued. The roster is on `World` and is not
  cleared by `level_init`.
- Buff scaffolding lands in 1.3: `BuffCategory`, the 5-slot array, `BUFF_DEFS`,
  `max_health`, and a seeded roll. 1.4 becomes buff effects plus
  `species_unlocked` wiring.
- Buffs roll at flee and are stored on the roster entry. The seed is
  `derive_seed(wave.seed, .Buff, slot_index)`. A sixth escape replaces the oldest
  buff.
- Fleeing is a zero-duration wave phase in 1.3. The wave is logically resolved at
  crossing, collision ignores `.Fleeing`, and advancement waits for the phase.
  The future animation only adds duration and motion.
- `Level.flee_prohibited` skips the threshold draw and uses `1000`. It has no CLI
  surface; verify with a temporary code edit.

## 1.3 step one: buff scaffolding (2026-11-06)

Implemented in `src/enemy.odin`; `odin check src` passes.

- `MAX_BUFFS :: 5`; `BuffCategory`; `BuffDefinition` and `BUFF_DEFS` with the
  unit of each category documented.
- `BacteriaHot.max_health` is set from `BACTERIA_DEFS` health in
  `bacteria_init`, and `health` is then restored from it.
- `BacteriaCold.buffs` and `buff_count` are cleared on every spawn, so a reused
  slot cannot inherit the previous occupant's buffs.
- `bacteria_buff_add` appends until full, then shifts slots 1–4 down and writes
  the new category at index 4. It is unused until the flee roll lands.
- All `BUFF_DEFS` magnitudes are `1` placeholders and no effect reads them yet.

Review notes not yet acted on:

- `BuffCategory` is ordered `Frenzied, Hardy, Resistant, Biofilm`, while the docs
  and `BUFF_DEFS` list `Hardy, Resistant, Biofilm, Frenzied`. Freeze the order
  before the seeded roll uses the enum ordinal.
- A magnitude of `1` is meaningful for Biofilm (one hit) but not for Resistant
  (1 permille) or Frenzied (1 speed point). Treat the values as provisional.
- `BacteriaState` was moved above `Sine_Dive`; unrelated to the scaffolding.
- `bacteria_buff_add` sits after `bacteria_animate`, outside the helper section.

## Current code state

`odin check src` is clean. Roadmap 1.2 is implemented end to end: ownership,
counters, spawn termination, crossing, completion, advancement, and `level_end`.
The first 1.3 item, buff scaffolding, is also in place but has no runtime
behavior. `fled_count` is still always zero, and `level_end` is written but
unread until `.Level_Transition` lands in 1.5.

Runtime verification: the crossing checks were reported passing — boundary,
set-once, shortfall denominator, and the zero-spawn guard. The resolution and
advancement checks are not recorded.

Two issues recorded in earlier sessions are fixed in the current source: the
wave guard uses `<` and `wave_dive_update` is guarded, and the overlay reads
`wave[wave_index]` consistently and within bounds.

## Current task

Roadmap 1.3, fleeing and returning. The design is settled and the buff
scaffolding is implemented; the rest of the slice has not started. 1.2 is
complete; 1.6 verification stays outstanding behind it.

## Next step

Continue 1.3 in roadmap order: add the `.Buff` seed category and store `seed` on
`Wave`, then the FIFO roster on `World`, the flee-prohibited flag, the effective
threshold, the zero-duration flee phase, roster scheduling and capacity, the
return spawn path, then logs and verification.

Before the seeded buff roll lands, settle the `BuffCategory` order and the
`BUFF_DEFS` magnitudes. The existing crossing branch in `wave_update` is the only
1.3 seam. `Level.end_chance` still needs confirming and removing before 1.5.

## Open issues

- `BuffCategory` order differs from the documented order. It becomes part of
  deterministic replay once the seeded roll indexes the enum, so settle it before
  that roll lands.
- `BUFF_DEFS` magnitudes are `1` placeholders; 1.4 owns tuning.
- `Level.end_chance` is unread and superseded by the rolled flee threshold;
  `Level.level_end` is written but unread until 1.5.
- `--no-vsync` is parsed but never read; the renderer always enables vsync.
- `species_unlocked` is computed but never read; `bacteria_spawn` hardcodes
  `.Strep`.
- Decisions still read wall-clock time: `formation_complete_time`, the dive
  gate, and `delta_time`.
- `wave_init` writes `region_enemy_count[i] = result.placed` for every region,
  i.e. the full total into each. Correct while `compute_formation_bounds`
  returns 1; wrong when it returns more.
- `wave_init` assigns `spawn_region = 0` twice.

## Verification to record

1.3 buff scaffolding: compile clean; no runtime behavior yet. Still to record:

- a reused pool slot starts with `buff_count == 0` and base `max_health`
- seven `bacteria_buff_add` calls leave the five newest, in order, with
  `buff_count == 5`

1.3 flee and return: not yet run.

- level 11: kill to the threshold; the remaining bacteria enter `.Fleeing`,
  `fled_count` matches, but the wave advances only after the flee phase
- returners appear first in the next wave, preserve species, and spawn with
  restored health and their buff
- a carried bacterium flees again: new buff, no escape counter; a sixth escape
  replaces the oldest buff
- a full roster drops the oldest; due overflow stays queued
- flee-prohibited via temporary edit: no threshold draw, nothing flees, full
  clear required
- same seed twice: same thresholds, roster contents, and buff rolls
- collision ignores `.Fleeing`; a fleeing bacterium cannot be killed or counted
  twice

1.2 crossing: reported passing.

- boundary at the threshold fraction (cross at 3 of 5 for a 500-per-mille wave)
- set-once: later kills do not re-log
- shortfall wave: crossing uses `spawn_count` as the denominator, not
  `enemy_count`
- zero-spawn wave: no crossing, shortfall log only

1.2 resolution and advancement: not recorded. The checks are

- `--level 11`, five enemies: four destroyed logs the crossing but does not
  advance; the fifth logs resolution and advancement
- multi-wave level: one advancement per wave, `level_end` only after the last
- no stranded bacteria when a wave is left partly alive at low threshold — this
  is the check that separates completion from crossing
- overlay with `--debug` after `level_end` reads a valid wave
- same seed twice: advancement on the same frames

Counters slice: not yet recorded. The checks that prove the increment is
attributed once and to the right wave:

- kill one bacterium → `destroyed_count == 1`, `fled_count == 0`,
  `resolved == 1`
- two bullets into the same bacterium in one frame → still 1
- kill one, let the wave respawn into the freed slot, kill that → 2
  (the recycled-slot case the old index array got wrong)
- kill a whole wave → `destroyed_count == spawn_count`
- same seed twice → the same counts at the same points

Spawn bound: forcing `region_enemy_count[0] = 2` with `enemy_count == 5` should
give two spawns, `spawn_finished == true`, `spawn_count == 2`, and no read of
region 1. Not yet run.

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

## Problems discovered in the crossing and resolution slice

- **Completion gated on crossing.** The first `wave_resolution_update` advanced
  when `threshold_crossed` was set, not when `resolved == spawn_count`, so a wave
  advanced with bacteria still alive and left them stranded in the pool, owned by
  a wave that no longer existed. Level 1 hides this: its threshold is 900–1000,
  so crossing and completion happen on the same kill. Any level with a real
  threshold (11+) separates them.
- **A log outside its condition.** The first resolution line was placed before
  the predicate, so it printed every frame and buried the crossing and
  advancement lines. A log that fires on every frame is worse than no log: it
  looks like the channel works while the actual events scroll past.

## Problems discovered in the counters and spawn-bound slice

- **An unassigned bound.** `wave_init` computed `region_count` for the entry
  loop and never stored it on the wave. The walk's bound was therefore `0`, so
  the loop body never ran and the exhaustion branch never fired. The guard was
  inert in exactly the case it existed for.
- **`>` where the walk guarantees `==`.** Exhaustion is `spawn_region ==
  region_count`; testing `>` fell through to the spawn branch and read region
  `region_count`, which is outside the filled regions.
- The two masked each other: with `region_count == 0` the bad comparison was
  unreachable, and with the comparison fixed the missing assignment would have
  read past the filled regions instead. A guard that never executes is not
  tested by playing the game normally; it has to be forced.

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
