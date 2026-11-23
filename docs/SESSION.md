# Current Session

## Date

2026-11-23 (1.4 implemented; species dives are placeholders)
2026-11-21 (1.4 decisions settled and docs updated; implementation not started)
2026-11-19 (1.3 steps one–six plus the return spawn path, verified; 1.2
complete 2026-11-05; earlier work 2026-11-01 and 2026-10-31)

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
- Fleeing is a zero-duration wave phase in 1.3. Crossing marks the rest
  `.Fleeing`; advancement waits for the phase. Revised 2026-11-15: fleeing
  bacteria stay targetable, and `fled_count` is incremented at finish so a phase
  kill counts only as destroyed. The future animation only adds duration and
  motion.
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

## 1.3 step two: `.Buff` seed and `Wave.seed` (2026-11-13)

- `.Buff` is appended to `SeedCategory`, after `.Level`, so existing category
  ordinals and all previously derived seeds are unchanged.
- `Wave.seed: u64` stores the wave seed, assigned in `wave_init` before any
  derivation.
- The existing entry and threshold derivations still use the local `wave_seed`.
  The stored field is unread until the flee roll lands.

## 1.3 step three: return roster (2026-11-13)

- `PendingBacteria` stores species, buffs, `buff_count`, and
  `waves_until_return`. `ReturnRoster` is a compact `[MAX_ENEMIES]` array plus a
  `count`; both live in `src/enemy.odin`.
- `World.return_roster` is zeroed in `world_init`. `level_init` takes only
  `^Level`, so it cannot clear the roster.
- `return_roster_push` appends until full, then shifts the filled portion down and
  drops the oldest entry. `return_roster_pop` removes index 0, shifts the
  remainder, decrements `count`, and zeroes the vacated tail.
- A temporary `return_roster_self_test` ran at startup and passed under the dummy
  SDL video driver: empty pop, FIFO order, cap at `MAX_ENEMIES`, and dropping the
  two oldest on overflow. The check was removed after the run.

## 1.3 step four: flee phase (2026-11-15)

- `Wave.flee_phase_active` marks the phase. `wave_flee_begin` marks every active,
  owned bacterium `.Fleeing`, rolls its buff, and records `flee_start_time`.
- `wave_flee_update` runs after `wave_update` and before `wave_resolution_update`.
  The phase is zero-duration, so it calls `wave_flee_finish` immediately.
- `wave_flee_finish` pushes each survivor into the roster, deactivates the slot,
  clears ownership, and increments `fled_count` per survivor. A bacterium killed
  during the phase is already inactive, so it is neither pushed nor counted as
  fled.
- `fled_count` therefore settles at finish, not at crossing. The
  `flee_phase_active` check in `wave_resolution_update` is load-bearing: killing
  every fleeing bacterium mid-phase makes `destroyed_count` reach `spawn_count`
  before finish runs.
- Fleeing bacteria stay targetable; collision has no `.Fleeing` skip. With a
  zero-length phase this is unobservable in 1.3 and is verified with the
  animation.
- Logs: `flee begin` reports the candidate count, `flee finish` reports
  `fled_count`, roster count, and elapsed milliseconds from `sdl.GetTicks()`.

## 1.3 step five: buff roll at flee (2026-11-15)

- `BuffCategory` is reordered to `Hardy, Resistant, Biofilm, Frenzied`, matching
  the docs. The order is now frozen because it indexes the seeded roll.
- The picker casts `rand.int_range(0, len(BUFF_DEFS))` to `BuffCategory`; the
  range derives from the table, so adding a category cannot silently shorten the
  roll. The roll is inlined in `wave_flee_begin` rather than kept as a helper.
- `wave_flee_begin` derives one RNG per escaping bacterium from
  `derive_seed(wave.seed, .Buff, slot_index)` and appends the roll with
  `bacteria_buff_add`. A sixth escape replaces the oldest.
- `wave_flee_finish` is unchanged: it copies `cold.buffs` and `cold.buff_count`
  into the entry, so the new buff rides along.
- The roll happens at begin, so the pool slot carries the buff during the phase.
  A bacterium killed mid-phase discards the roll with its slot. `bacteria_init`
  clears buffs on reuse.
- `BuffCategory`'s zero value is now `Hardy`, so unused slots past `buff_count`
  read as Hardy. Consumers must iterate to `buff_count` only.

## 1.3 step six: queue scheduling (2026-11-19)

- `return_roster_tick` decrements every `waves_until_return > 0` across the
  filled portion of the roster. Due entries stay at zero.
- `wave_resolution_update` now returns `bool`, true only on the frame a wave
  completes. `world_update` calls `return_roster_tick` only when it returns true,
  so the tick runs once per completion rather than once per frame.
- The tick runs at the end of the wave the bacterium fled from, after
  `wave_flee_update` has pushed it. A pushed delay of one becomes zero in the
  same frame, so the entry is due for the next wave.
- Update order is load-bearing: `wave_flee_update` must stay before
  `wave_resolution_update`, or an entry misses its tick and returns a wave late.
- The tick also runs for the last wave before `level_end`, so a last-wave escape
  is due for the next level's first wave once 1.5 lands.
- No entry is ever observed at delay one between frames; delays above one are
  only reachable through a temporary test edit.

## 1.3 return spawn path (2026-11-19)

- `BacteriaSpawnParams` carries `buffs` and `buff_count`; `bacteria_init` copies
  them onto the slot instead of clearing them, so a reused slot inherits the
  roster entry's buffs while fresh spawns pass a zeroed array and count.
- `wave_update` takes the roster, peeks `return_roster_front_due` at each spawn
  tick, builds the same entry path and destination either way, and pops only
  after `bacteria_spawn` succeeds. Species, buffs, and `wave_index` come from the
  entry for a returner; fresh spawns still use `.Strep`.
- Health is restored to base/max by `bacteria_init`; Hardy's magnitude stays a
  placeholder until 1.4.
- Verified headlessly with a temporary forced crossing under the dummy SDL
  driver: returners lead each wave, buffs compound 1→5 with the cap holding,
  health reads 6/6 on every return, one deferred entry returned a wave late, a
  preloaded roster capped at 50 with the oldest dropped, flee-prohibited logged
  1000‰ on all waves, and two same-seed runs produced byte-identical 72-line
  logs. All temporary edits were reverted; source hashes were unchanged.
- The full-pool spawn-failure case and a phase kill remain untested at runtime.

## 1.3 remaining logs (2026-11-19)

- Three lines landed: `[roster] push` in `wave_flee_finish`, `[roster] drop` in
  `return_roster_push`, and `[wave %v] flee prohibited` in `wave_init`.
  Flee begin/finish, per-slot buff, and return logs already existed.
- Both roster logs report `buff_count`, not the raw `buffs` array. The raw array
  prints unused slots as `Hardy` (zero value), which reads like five buffs; the
  specific category is already carried by the `flee: slot=` line.
- The drop log captures `roster.entries[0]` before the shift loop. After the
  loop, index 0 has been overwritten with `entries[1]`, so logging there would
  name the wrong entry.
- `core:fmt` returned to `src/enemy.odin` for the drop log; it is used, so the
  deferred vet errors at gate 1.8 are unchanged.
- Verified headlessly with temporary edits, all reverted and source hashes
  matched: 48 near-cap preload + 4 fled produced two `drop` lines with
  `roster=50` (cap held), push lines matched the flee lines on species and
  buff count with delay 1, and the temporary flag logged `flee prohibited`
  once per wave alongside `permille = 1000`.
- `flee prohibited` is emitted at init, not at crossing, so it prints per wave
  whether or not the wave actually flees.

## 1.4 decisions (2026-11-21)

No source changed in this pass; decisions recorded in `DECISIONS.md` and the
roadmap, architecture, and current-state docs updated to match.

- Weapon weakness is removed. One `damage` value per weapon;
  `BacteriaDefinition.weakness` and `calculate_bullet_damage` are deleted.
  `WeaponType` stays as identity. Reason: the system could not be made to work;
  progression moves to the skill tree.
- The player starts with Neutral only. No switching control exists today, so none
  is added in Phase 1; Phase 7 adds unlocks, switching, active abilities and
  passive stat nodes. PCN and PMX remain stat-identical placeholders until then,
  to be tuned along a damage-versus-fire-rate tradeoff.
- Buff magnitude is a normalized permille fraction of a per-category ceiling in
  `BUFF_DEFS`, stored per instance on the buff slot and roster entry. Reverses the
  earlier category-only, absolute-magnitude rule; the reason is that level scaling
  and a lucky/unlucky range make magnitude instance data.
- Total magnitude per category is capped at its ceiling: additive-with-cap,
  resolving the Frenzied stacking question. Per-category because the units differ
  (health %, damage permille, hit count, speed %).
- Fraction bands reuse the 5-level blocks. Proposed starting bands in permille of
  ceiling: `[20,40]`, `[100,200]`, `[200,400]`, `[300,600]`, `[500,1000]` for
  blocks 0–4+. Numbers are tuning, not architecture.
- The category stays the first draw from the per-slot RNG; the fraction is a new
  second draw. The flee threshold's `+50 * max_buff_count` is out of scope.
- `species_unlocked` wiring is a separate third substep, after weakness removal
  and buff effects.
- Discrepancy found: `PROJECT.md` claimed weapon selection was implemented.
  `current_ammo` is never written after `player_init`; corrected.

## 1.4 implementation (2026-11-23)

- **A. Weapon weakness removed.** `WeaponDefinition` collapsed to a single
  `damage`; `BacteriaDefinition.weakness` and `calculate_bullet_damage` deleted.
  Neutral, PCN, and PMX are all `damage = 3` placeholders; Phase 7 tunes them.
- **B. Buff effects.** `BuffInstance` carries category and rolled fraction;
  stored on `BacteriaCold`, spawn params, and roster entries. `BUFF_DEFS` holds
  per-category ceilings and `BUFF_FRACTION_BANDS` holds the 5-level permille
  bands. `buff_total` converts each matching slot and caps the sum at the
  ceiling, with the Biofilm floor applied only when a Biofilm slot exists.
  Hardy and Frenzied are applied in `bacteria_init` (health restore moved below
  them); Resistant and Biofilm are applied by `bacteria_dmg_after_buffs` at the
  damage site in `game.odin`. `biofilm_hits` is reset on spawn.
- **Flee roll.** `wave_flee_begin` draws the category then the fraction from the
  per-slot RNG, stores both, and logs the fraction.
- **C. Species variety.** Fresh spawns draw from
  `derive_seed(wave.seed, .Wave, 1 + spawn_index)` against
  `min(species_unlocked, len(BACTERIA_DEFS))`; returners keep their stored
  species. `wave_init` now stores `species_unlocked` (it had been computed but
  never assigned, so the draw started at `int_range(0, 0)` and asserted).
- **All-species placeholder motion.** Entry and return bezier movement are
  duplicated per species, and `entry_path_length` is set for all four in
  `bacteria_init` and `bacteria_return_init`. E. coli's `Zigzag_Dive` advances a
  timer, flips direction on cooldown, moves horizontally and downward, and
  bounces off the screen edges. Pseudomonas's `Sweep_Dive` copies its four
  control points into a temporary `EntryPathData` and reuses `bezier_calc` over a
  fixed two-second placeholder duration. Every dive type now sets
  `return_start_points`, `t = 0`, `dive_initialized = false`, and
  `return_initialized = false` when it enters `.Returning`.
- `return_initialized` reset is load-bearing for repeated dives: without it the
  second return reused the first return's path. This was latent for Strep.
- The duplicated non-Strep blocks and the hardcoded dive speeds are deliberate
  placeholders for Phase 6; Frenzied still reaches only Strep motion.

## Current code state

`odin check src` is clean. Roadmap 1.2 and 1.3 are implemented end to end.
Roadmap 1.4 is implemented: weakness removed, all four buff effects live,
species drawn from the seeded pool, and all four species enter, dive, and
return. The non-Strep entry/hold/dive/return blocks and the hardcoded dive
speeds are placeholders for Phase 6. `level_end` is written but unread until
`.Level_Transition` lands in 1.5.

Runtime verification: the 1.3 flee/return checks were exercised headlessly with
a temporary forced crossing, including same-seed replay. The 1.4 species and
buff effects have not been recorded as standalone runtime runs yet.

Two issues recorded in earlier sessions are fixed in the current source: the
wave guard uses `<` and `wave_dive_update` is guarded, and the overlay reads
`wave[wave_index]` consistently and within bounds.

## Current task

Roadmap 1.4 is implemented in source and `odin check src` is clean. Remaining
work is to verify 1.4 at runtime: species per level, dives and returns, buff
effects, and same-seed replay.

## Next step

Run the 1.4 verification checks below, then start 1.5 (`Level_Transition`).
`Level.end_chance` still needs confirming and removing before 1.5.

## Open issues

- `BUFF_DEFS` ceilings and `BUFF_FRACTION_BANDS` are first-pass tuning values,
  not architecture.
- Weapon damage is a flat `3` for Neutral, PCN, and PMX; differentiation is
  Phase 7 work.
- No weapon switching control exists; `current_ammo` is set once in `player_init`.
- Remaining `odin check src -vet` errors are deferred to roadmap gate 1.8 at
  the end of Phase 1: `ttf` in `debug.odin`, two unused `bacteria_def` locals in
  `enemy.odin`, and `divers_count`/`potental_divers` in `procedural.odin`.
- `BuffCategory`'s zero value is `Hardy`, so unused buff slots past `buff_count`
  read as Hardy. Any consumer must loop to `buff_count`.
- Frenzied affects only Strep entry and dive motion; Staph, E. coli, and
  Pseudomonas dive speeds are hardcoded placeholders (Phase 6).
- Non-Strep entry/hold/dive/return behavior is duplicated placeholder code; each
  copy repeats the wall-clock `state_start_time` read, widening the Phase 2
  determinism fix.
- The full-pool spawn-failure path in `wave_update` (no pop, no counter advance)
  is structurally correct but untested at runtime; it needs a temporary edit
  that fills all `MAX_ENEMIES` slots before a spawn tick.
- Fleeing bacteria remain targetable, but the phase is zero-length in 1.3, so a
  phase kill cannot be observed and the counter rule is unverified.
- `fled_count` settles at finish, which makes the resolution gate load-bearing;
  the gate has not been exercised with a deferred finish.
- `Level.end_chance` is unread and superseded by the rolled flee threshold;
  `Level.level_end` is written but unread until 1.5.
- `--no-vsync` is parsed but never read; the renderer always enables vsync.
- Decisions still read wall-clock time: `formation_complete_time`, the dive
  gate, `flee_start_time` (log only), and `delta_time`.
- `wave_init` writes `region_enemy_count[i] = result.placed` for every region,
  i.e. the full total into each. Correct while `compute_formation_bounds`
  returns 1; wrong when it returns more.
- `wave_init` assigns `spawn_region = 0` twice.

## Verification to record

1.4 compile: `odin check src` is clean. Runtime checks still to record:

- level 1: Strep only; level 6 adds Staph; level 11 adds E. coli; level 16 adds
  Pseudomonas
- every fresh spawn has a finite nonzero `entry_path_length` and reaches
  `.Holding`; every species dives and returns without stale positions
- E. coli zigzags and bounces off the screen edges; Pseudomonas sweeps along its
  curve; both return from their dive exit point
- Hardy raises `max_health`; five block-4 Hardy rolls give exactly `base * 6`
- Frenzied raises Strep entry and dive speed
- Resistant reduces damage and floors at 1; Biofilm absorbs exactly its rolled
  hit count and resets on spawn/return
- Biofilm with no buff absorbs nothing; an early low-fraction Biofilm still
  absorbs one hit
- a second dive in the same life returns along its own new path, not the first
- same seed twice: identical species per slot, entry positions, buff fractions,
  and dives

1.3 seed and roster: compile clean. The temporary startup roster self-test passed
under the dummy SDL video driver and was removed: empty pop, FIFO order, cap at
`MAX_ENEMIES`, and dropping the two oldest on overflow. Still to record:

- same-seed run after appending `.Buff`: wave composition, formations, and
  thresholds unchanged from the pre-change build
- a roster entry survives `level_init` (structurally guaranteed by the `^Level`
  signature, but not exercised)

1.3 buff scaffolding: compile clean; no runtime behavior yet. Still to record:

- a reused pool slot starts with `buff_count == 0` and base `max_health`
- seven `bacteria_buff_add` calls leave the five newest, in order, with
  `buff_count == 5`

1.3 flee phase: compile clean; not yet run. The checks are

- level 11: kill to the effective threshold; the remaining bacteria log
  `flee begin`, `fled_count` matches at `flee finish`, the roster grows by that
  count, and the wave advances only after finish
- roster entries carry the remaining species, `waves_until_return == 1`, and the
  freed slots are inactive with `OWNER_NONE`
- `flee finish` elapsed time is reported; it is `0ms` or `1ms` in 1.3
- defer `wave_flee_finish` by a few frames temporarily: the wave must not advance
  while `flee_phase_active` is true, and must advance on the frame finish runs
- prohibited wave: full clear produces no flee phase, no roster entry, and one
  advancement
- a phase kill counts as destroyed and produces no roster entry; deferred with
  the animation because the phase is zero-length

1.3 buff roll: compile clean; not yet run. The checks are

- level 11 forced crossing: each escaping bacterium logs one category, and each
  roster entry has `buff_count == 1` matching the begin log
- same seed twice: identical category per slot per wave
- different slots get independent rolls; a five-member wave should not roll a
  single category
- a sixth escape replaces the oldest: temporary direct test of six
  `bacteria_buff_add` calls
- a phase kill leaves no roster entry and discards its roll (latent at zero
  duration)

1.3 queue scheduling: compile clean; not yet run. The checks are

- forced crossing: after the flee wave completes, every roster entry has
  `waves_until_return == 0`
- temporary delay of 3 in `wave_flee_finish`: it steps 3 → 2 → 1 → 0 across
  successive wave completions and never goes below zero
- a wave that completes without an escape still ticks older entries; an empty
  roster makes the tick a no-op
- last wave: `level_end` is set and the tick still ran
- same seed twice: same delays on the same frames

1.3 flee and return: verified 2026-11-19 under the dummy SDL driver with a
temporary forced crossing (no automated input can land kills). All temporary
edits were reverted and the source hashes matched the pre-test state.

- returners appear first in the next wave, preserve species, and spawn with
  restored health and their buff — passed; `health=6/6` and `species=Strep`
  on every return line across all six waves
- a carried bacterium flees again: new buff, no escape counter; a sixth escape
  replaces the oldest buff — passed; counts compound 1→2→3→4→5 and never
  exceed five, with the cap replacing the oldest
- a full roster drops the oldest; due overflow stays queued — passed; 48
  preloaded + 4 fled left `roster=50`, and the one entry left queued by wave 2
  returned in wave 3
- same seed twice: same thresholds, roster contents, and buff rolls — passed;
  two runs produced byte-identical 72-line logs
- flee-prohibited: passed; all six waves logged `flee prohibited` and
  `permille = 1000`
- 1.3 logs: passed; push lines matched flee lines on species and buff count with
  delay 1, two `drop` lines fired on a near-full roster with `roster=50`, and
  the flag logged once per wave
- not covered: the full-pool spawn-failure path, and a phase kill (deferred to
  the animation step because the phase is zero-length)

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
