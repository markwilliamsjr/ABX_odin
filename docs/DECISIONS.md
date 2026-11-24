# Decisions

## Documentation conventions

### Decision

`ARCHITECTURE.md` describes *intent* — the game as designed, not as currently
implemented. `PROJECT.md` describes *current state*.

### Reason

The project has a design ahead of its implementation. The architecture document
was written as a statement of the intended game, and reading it as a description
of shipped behavior makes it look wrong when it is not.

### Consequences

- Do not treat a gap between `ARCHITECTURE.md` and the code as a contradiction.
  Such gaps are the unfinished state of a design the docs already describe
  accurately.
- `PROJECT.md`'s "Current State" is the only document claiming systems exist, so
  it is the one that most needs an explicit label. It now carries one.
- Every `ARCHITECTURE.md` mechanism is intent until code exists for it.

## Game structure

### Decision

A level is a sequence of waves. Some levels contain a single wave; others
contain more.

### Reason

Needed to give meaning to the existing `[MAX_WAVES]Wave` array and to distinguish
`wave_index` (position within the current level) from `wave_count` (global
running total).

### Consequences

- Two distinct counters are required. Conflating them is easy and hard to notice.
- `Level.wave_count` is the current level's own wave total, drawn from the level
  seed. A separate `wave_index` tracks position within the current level. An
  earlier reading of `wave_count` as a run-wide total is superseded: nothing
  accumulates across levels.
- `ARCHITECTURE.md` describes a wave's contents in detail but says almost nothing
  about what a *level* is. That gap is now closed here.

## Level composition

### Decision

The number of waves in a level is determined by a seeded random draw, with the
range growing as the level increases.

### Reason

Fits the project's stated goal of procedurally generated seeded levels, and makes
level structure itself part of what the seed determines.

### Consequences

- The RNG is consulted for level *structure*, not only wave contents. This is a
  deliberate widening of where randomness enters the system.
- The draw must be clamped to `MAX_WAVES`.
- The level-end condition is that all of a level's waves are resolved.

## Enemy counts

### Decision

`3 + level * 2` is a **level-wide enemy budget**, not a per-wave count. `level_init`
splits it across the level's drawn waves:

- `base = budget / wave_count`; the remainder `budget % wave_count` goes one each
  to the earliest waves, so the shares sum exactly to the budget.
- Every share has a floor of **3**, and **the floor wins**: if
  `wave_count * 3 > budget`, the level exceeds its budget.
- Each share then takes a seeded jitter (band defined under "Early-level
  determinism"), clamped to `[3, MAX_ENEMIES]`.

Naming follows the split: `WaveParams.total_enemies` becomes `enemy_budget`,
`Wave.total_enemies` becomes `enemy_count`, and `wave_init` takes `enemy_count` as
an explicit argument instead of reading it from the params struct.

### Reason

The original intent was a level budget split over waves, but `wave_init` never
sees `wave_count`, so the value had quietly become per-wave. The two readings are
not close: under the per-wave reading a level-10 level fields 69–138 bacteria
(23 per wave times 3–6 waves), against a budget of 23. The shared name made the
drift invisible, and the roadmap's threshold table was written against the drifted
meaning.

Passing the count explicitly follows the `level_number` precedent: a function's
inputs are visible at its call site, and `wave_init` cannot consume the budget by
accident once it never receives it.

Floor-wins was chosen over shrinking the drawn wave count because `wave_count` is a
seeded structural draw; quietly reducing it to fit the budget would make the level
disagree with its own seed. It was chosen over a soft floor because a one- or
two-enemy wave makes the flee threshold nearly meaningless.

Three is a provisional floor: high enough that a wave is more than a couple of
kills, low enough that the budget stays roughly honest.

### Consequences

- Levels can exceed their budget. With the early wave-count ramp this happens at
  levels 4, 6 and 7 only, by at most 3 bacteria. The budget is a difficulty target,
  not an allocation invariant.
- Per-wave size stays roughly 3–6 for the whole run; level length carries most of
  the growth. This is the count analogue of the wave-count curve, and it changes
  what the threshold table describes.
- The `MAX_ENEMIES` clamp becomes defensive. `3 + level*2` exceeds 50 from level
  24, but the budget is never indexed directly — only the split share is — so the
  overflow is removed structurally by the split. The clamp stays as the guard for
  the case where one wave carries the whole budget, and as the final bound on a
  share.
- At 3–6 enemies one kill is 167–333 permille, so threshold crossings are
  coarse. The threshold remains scale-free (a per-mille fraction destroyed).
- The count jitter band is ±1. It was ±3 while per-wave counts were assumed to
  be 5–43; the budget split made shares 3–6, so a wider band would swamp the
  share itself.

## Early-level determinism

### Decision

Generation variance ramps with level. Early levels are close to authored; later
levels are heavily seed-sensitive.

- **Wave count**: block 0 (levels 1–5) draws `[1, min(level, 4)]`. Level 1 is
  always one wave, level 2 one or two, level 3 one to three, levels 4–5 one to
  four. Blocks 1+ keep their existing ranges.
- **Per-wave count jitter**: band 0 in block 0, ±1 from block 1 onward.
- **Entry point**: levels 1–2 pin entry to top-center (`ENTRY_POINTS[2]`); levels
  3+ draw from the full set.

Ranges are drawn inclusively; see "Range semantics". The earlier exclusive
behaviour is superseded.

### Reason

The determinism contract says the same seed reproduces the same run. It says
nothing about how much a level changes when the seed changes. The intended feel is
an authored, predictable opening that becomes procedurally varied as the run
progresses, matching how wave counts and thresholds already scale.

Without the ramp the opening was the most seed-sensitive part of the run: block 0's
`1–4` is the widest relative range in the game (4x), while block 4's `9–10` is the
narrowest. A level 1 could be a single five-enemy wave or four waves of three,
entering from any of fifteen points.

Pinning entry through a one-element `available_points` slice reuses
`generate_entry_points` unchanged. A deterministic flag or an early branch inside
the generator would add a second code path for the same outcome.

### Consequences

- Level 1 is structurally identical across seeds: one wave, five enemies, same
  formation, same top-center entry. Its `threshold_permille` still varies over
  900–999, but that is unobservable: a five-enemy wave crosses every threshold in
  that band only at full destruction.
- Degenerate ranges no longer arise from the count draws: under inclusive
  semantics the upper bound is always above the lower. Guards that existed only
  to avoid a panic are therefore redundant. The band-0 jitter still skips its
  draw because zero jitter is the rule, not because the range is empty;
  skipping remains harmless because every draw site owns a throwaway RNG.
- The floor/budget overrun is confined to levels 4, 6 and 7.
- Level 5 to 6 has a structural discontinuity: the maximum rises 4 to 6 while the
  minimum jumps 1 to 3. It is inherited from block-based ranges, not introduced by
  the ramp.
- If formation regions ever multiply, the pinned entry slice must hold at least
  `region_count` points, or `generate_entry_points` returns `ok = false`.
- Later variance sources (formation variety, species choice) should be gated by
  level the same way, so the opening does not drift back toward generated.

Wave-count ranges by block (5 levels per block; the table is the intended
inclusive range):

| block | levels | range |
|-------+--------+-------|
|     0 |    1–5 |   1–4 |
|     1 |   6–10 |   3–6 |
|     2 |  11–15 |   5–8 |
|     3 |  16–20 |   7–10 |
|     4 |  21–25 |   9–10 |
|    5+ |    26+ |    10 |

Block 0 draws `[1, min(level, 4)]`: level 1 is always one wave, level 2 one or
two, level 3 one to three, levels 4–5 one to four. Adjacent blocks overlap by
two values, so escalation is non-decreasing rather than strictly increasing.
`MAX_WAVES` is 10.

## Range semantics

### Decision

Ranges are inclusive, and the documented ranges are the source of truth.
Odin's `rand.int_range` is exclusive at the upper bound, so every draw site
passes `hi + 1` rather than rewriting the range to match the API. This covers
the block-0 wave count, the block 1+ wave count, the per-wave count jitter, and
the flee-threshold spread.

### Reason

The wave-count table, the count jitter, and the threshold spread were all
written as if the range were inclusive. Treating the table as the specification
keeps one description of intended behaviour instead of two.

The jitter made the cost visible: `int_range(-band, band)` with `band = 1`
produced only `-1` and `0`, so block 1+ waves were systematically smaller than
designed rather than merely short at the upper edge.

### Consequences

- Every draw of this kind adds one to its upper bound. A draw that keeps the
  API's native exclusive bound is now a bug, not a style choice.
- The `MAX_WAVES` clamp is applied before the `+1`, or a saturated block draws
  one past the cap. Block 3 is the boundary case: its raw maximum equals
  `MAX_WAVES`, so the clamped path has to trigger on `>=`, not `>`, or it falls
  through to the unclamped draw. Block 3 draws 7–10, block 4 9–10, and block 5+
  returns 10.
- Guards that existed only to avoid an `int_range` panic on a collapsed range
  are no longer required, because the upper bound is always above the lower.
  The level-1 shortcut is retained anyway; it is redundant but harmless, and it
  keeps level 1 from drawing a value it cannot use. The band-0 jitter still
  skips its draw, because zero jitter is the rule.
- The flee-threshold spread is symmetric ±50 again, superseding the `[-50, 49]`
  note under "Flee threshold".
- Regenerating an existing seed produces different wave counts and jitters than
  before. The budget-sum invariants are unaffected; empirical distributions
  must be re-derived rather than assumed.

## Wave resolution and membership

### Decision

Wave membership is carried by the bacterium, not by the wave. The `Bacteria`
pool lives inside `Level`, so a level is the scope in which membership is
meaningful. Each wave stores its own index, set at `wave_init`; each spawned
bacterium stores that index and clears it when it leaves play. A wave's
level-qualified identity is `(level_number, wave_index)`, derived where needed
rather than stored on the bacterium. `Wave.enemy_indices` is removed once the
formation check and diver selection stop reading it.

Ownership is its own invariant, not a cached view of `hot.active`. The sentinel
is `-1`, because wave index 0 is a valid owner. `level_init` resets the pool by
zeroing it and then writing the sentinel into every ownership slot, so a
recycled slot cannot inherit the previous occupant's owner. Death and fleeing
both clear ownership as part of leaving play.

Each wave tracks two counters: `destroyed_count` and `fled_count`. The resolved
count is their sum; there is no third field. Death increments destroyed.
Fleeing increments fled. Either one clears ownership. A bacterium marked
`.Fleeing` that is subsequently killed counts as destroyed, not fled: the fled
increment is taken at phase finish, so the two counters cannot both count the
same bacterium.

Wave resolution has three explicit cases: dead (resolved), fled (resolved and
scheduled to return), and still alive (unresolved).

The threshold test runs only after spawning has finished and the wave has at
least one member:

```
spawn_finished && spawn_count > 0 &&
destroyed_count * 1000 >= spawn_count * threshold_permille
```

It sets `threshold_crossed` once. A wave completes when spawning has finished,
`spawn_count > 0`, and `resolved == spawn_count`.

The resolution pass runs after spawning and dive updates in the frame. It
advances `wave_index` exactly once per completed wave. When `wave_index` reaches
`wave_count`, it sets `Level.level_end`; `.Level_Transition` remains the owner of
the actual transition.

Deaths are attributed at the moment health reaches zero, not by a later scan of
a slot array. The collision path receives the level, so the kill increments the
owning wave directly.

Wave resolution is split into two steps. This step lands ownership, counters,
the crossing test, completion, and advancement. Crossing the threshold sets and
logs `threshold_crossed` but removes nothing; `fled_count` remains zero.
Completion therefore still means all spawned bacteria destroyed. The flee
response is Phase 1.3.

### Reason

`enemy_indices` describes slots at spawn time. `find_free_bacteria_slot` recycles
a slot as soon as its occupant dies, so one index can describe two different
bacteria within the same wave, and dead indices remain in the array. A count
derived from it is unsound even before returning bacteria exist. Ownership is the
smallest identity that survives recycling.

The pool belongs to the level because the level is its lifetime: bacteria do not
survive a transition, while what does — the master seed, the game state and the
pending roster — already lives on `World`. That makes `level_init` the single
reset authority, which matters because a forgotten reset is silent: a stale
owner makes the formation check and diver count see a bacterium that is not in
the wave.

Ownership is stated separately from `active` so that "this bacterium belongs to
this wave" has exactly one authority. If ownership were derived from `active`,
every scan would need both flags, and any code that wrote one without the other
would become a latent correctness bug instead of a visible inconsistency.

The stored index is the wave's position in the level, not a composite
`(level, wave)` value, because the pool is level-scoped: only one level's
bacteria exist at a time. A composite would duplicate the level number on every
bacterium and create a second source of truth for which level the pool belongs
to.

Two counters keep the threshold meaningful. Fleeing must resolve a wave without
counting as destruction; one combined counter would make the fraction destroyed
rise when bacteria escape, which is the opposite of what the threshold measures.
Deriving resolved avoids a third value that can disagree with its inputs.

The spawning gate protects the denominator. `spawn_count` is the denominator, and
it grows while spawning. Without the gate, one kill early in a wave can cross
almost any threshold, and the rest of the wave's budget would be resolved away
before it ever spawned.

The gate is `spawn_finished`, not `spawn_count == enemy_count`. The equality means
"the budget was filled", which is a different question and is unreachable when
the formation cannot place the whole budget. `spawn_finished` means "no more
bacteria will spawn", which is the property the denominator actually needs.

The `spawn_count > 0` term keeps a degenerate wave inert. Without it, a wave that
spawned nothing satisfies `0 >= 0` and completes on its first frame, hiding the
generation bug that produced it.

Attribution at the moment of death avoids an ordering dependency. A later scan
would have to run before the next spawn recycles the slot; making that safe is
more fragile than incrementing the owning wave at the kill site.

Splitting the response out keeps the roster questions — next-wave accounting,
roster capacity, level transitions — out of the mechanics that must exist anyway.
The crossing branch is the only part that changes in 1.3.

### Consequences

- Ownership lives on `BacteriaCold` beside `bacteria_state`; it is identity, not
  per-frame transform data.
- Wave identity is the level number plus the wave's stored index rather than a
  run-wide counter, so no extra state is threaded through transitions. The
  bacterium stores only the index; the level is implicit in the `Level` that
  owns the pool.
- `Bacteria` moves from `World` to `Level`. Update, collision, rendering and the
  overlay read it through the level, and `Level_Transition` resets per-level
  runtime by re-running `level_init` rather than reaching into `World`.
- The wave index is stored on the wave so scans and logs do not need it passed
  alongside the wave pointer. Array position remains the lookup for advancement;
  the stored index is identity. Both are assigned together in `wave_init`.
- `enemy_indices` is deleted. The formation check, diver count, and diver
  selection scan the pool for bacteria owned by the wave; ownership alone
  answers membership, and `active` remains the render/update gate.
- Because `-1` is the sentinel and `0` is a valid owner, a zeroed
  `BacteriaCold` is not a valid "not in play" state. The sentinel pass is part
  of the reset, not an optimisation after it.
- `fled_count` stays zero until 1.3, so threshold crossing is observable only in
  logs during 1.2.
- `wave_init` must assign the wave's stored index and reset `spawn_count`,
  `spawn_index`, timers, `formation_complete`, `formation_complete_time`,
  `threshold_crossed`, and both counters. `level_init` must reset `level_end`,
  `wave_index`, and the bacteria pool (zero, then the sentinel pass).
- A failed `bacteria_spawn` must not increment `spawn_count`; otherwise the wave
  carries a phantom member that can never resolve.
- A formation that places fewer bacteria than `enemy_count` no longer stalls.
  `spawn_finished` is set when the region walk runs out, so a shortfall wave
  still forms up, crosses, and completes against `spawn_count` — the count that
  actually spawned, not the budget. `enemy_count` remains the intended budget and
  is read only by the spawn check and the shortfall log.
- `Level.level_end` is consumed by `.Level_Transition` to start the next level.
  The `wave_index < wave_count` guard stops wave updates while the level is
  ending.
- Temporary `fmt` logging is the verification channel until the Clay overlay
  lands. Remove it when the overlay carries wave state.
- This supersedes the "assign-and-display only" scope note under "Flee
  threshold": the crossing test now lands in 1.2 and the response in 1.3.

## Fleeing and returning

### Decision

Bacteria flee when the fraction of the wave **destroyed** reaches a per-wave
threshold, expressed in per-mille. That threshold is a seeded random draw, rolled
**once per wave** at spawn time and compared deterministically on every subsequent
frame.

Fled bacteria are not removed. They withdraw and return in a later wave,
strengthened by **resistance buffs**. On return they are restored to spawn max
health, which may itself be buff-boosted.

Strengthening is by resistance only. **Bacteria never change species.**

### Reason

Three separate reasons.

First, a single roll preserves determinism. A per-frame probabilistic roll would
make runs irreproducible, contradicting the determinism principle in
`PROJECT.md`. Rolling once at spawn and comparing thereafter keeps replay intact.

Second, fleeing-and-returning is the difficulty-escalation mechanism that
`ARCHITECTURE.md` describes as *"the next wave bacteria is determined by what the
player is not killing."* Bacteria that fled are by definition bacteria the player
did not kill. The document describes the effect; this specifies the cause.

Third, bacteria develop resistance rather than transforming. Modelling real
biology keeps `BACTERIA_DEFS` a clean const table, introduces no species mutation
anywhere, and makes the return path simple — nothing about species needs tracking
on a returning bacterium. An earlier draft of this decision specified tier
promotion on return; that was rejected because it contradicts how bacteria
actually behave.

### Consequences

- Fleeing is not a fail-state escape valve. It is the primary difficulty
  escalation engine.
- Wave resolution has **three** cases, not two: dead (resolved), fled (resolved
  *and* scheduled to return), still alive (unresolved).
- Fleeing is evaluated per wave, not per level.
- A fled bacterium requires a pending roster that outlives the wave, so that
  roster lives on `World`, not on `Wave`. See "Return scope".
- Return scheduling must use seeded RNG, or determinism breaks.
- **Pending bacteria carry across level boundaries.** They do not die at the
  end of a level. See "Return scope" below.
- This is a *partial* realization of the architecture doc's adaptive bias. True
  wave-composition bias — skewing spawns toward species the player is not killing
  — remains separate, deferred work that depends on a kill-count system that does
  not exist.
- Wall-clock time (`sdl.GetTicks()`) must not appear in any generation or
  threshold decision.
- **No species promotion, ever.** An earlier decision to promote fleeing
  bacteria only to already-unlocked species is superseded and no longer applies.
  There is no promotion to gate.
- `species_unlocked` is wired into spawn variety (1.4 substep C), not promotion.
  Fresh spawns draw a species from `derive_seed(wave.seed, .Wave, 1 +
  wave.spawn_index)` against `min(species_unlocked, len(BACTERIA_DEFS))`;
  returners keep their stored species. Level 1 therefore draws Strep only.

## Return scope

### Decision

The pending roster lives on `World` and **survives level transitions**.

A bacterium that flees enters the queue and is scheduled for the **next wave** —
one queue step, not a per-level dump. If it flees again, it is scheduled one wave
later again. The queue is FIFO. A level therefore never opens with a flood; the
backlog arrives one wave at a time.

Carried bacteria **may flee again**, rolling a fresh buff and receiving a fresh
health restore each time. There is no escape counter.

At a **boss level, all bacteria must be destroyed** before the player can advance.
Bosses are the pressure valve for the roster: fleeing is not permitted there, so a
fully-stacked bacterium must finally be killed. Boss levels are what eventually
force a hard clear. Before bosses exist, the per-bacterium stack is still bounded
at five slots; a sixth escape replaces the oldest buff.

Boss specifics — whether a boss is a separate level or a special wave, whether
fleeing is disabled outright or permitted but buff-free, whether a threshold is
rolled at all, and whether the roster enters or is spent before the boss — are
**deferred**. Only the flush behaviour is decided.

### Reason

Carrying was chosen over dropping the roster at level end, and over special-casing
the final wave.

Dropping creates an exploit: fleeing on the **last wave** of a level would be free,
because the level still counts as complete and the bacteria are gone forever. That
is not an edge case — the final wave is precisely where the flee threshold is most
likely to be crossed, so "let them all run on the last wave" becomes the optimal
strategy and defeats the escalation engine entirely.

Special-casing the final wave was rejected because it makes the level's climax
play by different rules than every other wave, and in the wrong direction: the last
wave would become *less* dangerous, which is backwards.

Carrying has no such problem, and its accumulation cost is already bounded by the
existing requirement to cap the roster against `MAX_ENEMIES`.

Bosses as the flush point are what make indefinite re-fleeing acceptable. Without a
periodic hard-clear, a bacterium could be escaped on indefinitely and the 5-slot cap
becomes the only thing holding the whole system together. With it, escapes are
bounded across a run and the roster develops a rhythm — build up, flush, rebuild —
rather than a monotonic ramp.

Disabling fleeing at boss levels gives the system a periodic hard clear. Before
boss levels exist, a bacterium with five buffs can escape again, so the fixed-size
array needs a rule: the new buff replaces the oldest.

### Consequences

- The roster lives on `World`, not `Level`. `Level_Transition` must **not** clear
  it — a change to what that state does when resetting per-level state.
- **No escape counter** exists on a bacterium. The 5-slot cap is load-bearing, not
  merely a safety bound. A sixth escape replaces the oldest buff; the slot count
  never grows.
- Because a carried bacterium can be escaped on repeatedly, the roster can grow
  faster than fresh spawns. Late levels risk becoming a wall of returning bacteria
  rather than a mix. A tuning concern, not a structural one.
- The boss system stops being purely cosmetic. The roadmap lists boss fights as
  deferred, but the flush behaviour is now part of the difficulty architecture and
  cannot be designed entirely later.
- At minimum, the current slice needs a way to mark a level as **fleeing
  prohibited**, even with no boss content. That is a small addition, but it means
  this slice is not fully independent of the deferred boss system.
- It is expected that bosses are infrequent — the meter in `ARCHITECTURE.md` is
  hidden and fills across levels — so escapes remain freely stackable *between*
  bosses. That appears intended rather than a gap.

### Open questions (not yet decided)

- **At boss levels, is fleeing disabled outright, or permitted but buff-free?**
  Only "disabled" makes "clear all bacteria" mean what it says.
- **Does the roster enter the boss level, or is it spent first?** Letting it arrive
  means the boss level is the hardest thing in the game by design — the player
  brings their worst case and must finally kill it. This appears dramatically
  stronger than flushing beforehand, but it is unconfirmed.
- **Boss shape.** Separate level, or special wave within a level? If a special
  wave, the other waves in that level follow normal flee rules.

## Return queue mechanics

### Decision

The roster is a FIFO on `World`, capped at `MAX_ENEMIES`. Each entry stores the
bacterium's species, its buffs, and `waves_until_return`. A bacterium that flees is
added with a delay of one wave. When a wave completes, every pending delay above
zero is decremented; entries at zero are due. Due entries are consumed at spawn
time, before fresh bacteria, and each consumes one of the wave's existing spawn
slots. Fresh bacteria fill the remaining slots. If more entries are due than the
wave can hold, the remainder stays due for the following wave.

When the roster is full, adding a fled bacterium drops the oldest entry.

### Reason

Reusing the next wave's spawn slots keeps `enemy_count`, the generated formation,
and the `MAX_ENEMIES` pool bound unchanged. Adding returners on top would require
extra formation positions and could exceed the pool. FIFO keeps the return order
deterministic and reads "positionally" as queue order.

### Consequences

- `spawn_count` includes returning bacteria, so they count toward the wave's
  threshold denominator and must be resolved before it completes.
- A returning bacterium can flee again; it re-enters the queue for the following
  wave and gains another buff.
- A large backlog may take several waves to clear. That is the intended "one wave
  at a time" behaviour, not a dropped return.
- The roster is initialized in `world_init` and must not be cleared by
  `level_init` or `Level_Transition`.
- The roster is a compact array with the oldest entry at index 0. Push and pop
  shift only the filled portion. At `MAX_ENEMIES` the copy cost is irrelevant,
  and chronological order stays readable in logs and a debugger.
- Returners spawn with their preserved species and restored health, using the next
  wave's entry path and formation position.
- The delay decrement runs at the completion of the wave the bacterium fled
  from, after the flee phase has pushed it. A delay of one therefore means "due
  for the next wave". This makes the update order load-bearing: flee finish must
  run before wave resolution, or the entry misses its tick and returns a wave
  late.

## Flee animation phase

### Decision

The flee response is a short wave phase. In 1.3 the phase has zero duration.
Crossing the threshold marks the remaining bacteria `.Fleeing` and sets the phase
active, but does not advance the wave yet. Advancement waits until every fleeing
bacterium finishes the phase. At finish, each survivor is pushed into the roster
and `fled_count` is incremented, then its ownership is cleared and its slot
deactivated.

Fleeing bacteria remain valid collision targets. A bacterium killed during the
phase increments `destroyed_count`, is not pushed into the roster, and does not
count as fled. Future animation work adds a duration and exit motion to the
phase; it does not change resolution or roster ownership.

### Reason

Waiting for the phase avoids two separate problems: the next wave starting while
the previous wave's bacteria are still leaving, and fleeing bacteria needing a
visual-only representation outside the pool. The pool and ownership stay valid
for the whole phase. Keeping fleeing bacteria targetable makes the escape
contestable: the player can deny a return by finishing the job during the phase.

### Consequences

- The wave is headed for resolution at crossing, but its counters are only
  complete at finish. `fled_count` counts escapes that actually happened.
- The `flee_phase_active` gate in `wave_resolution_update` is load-bearing: if
  the player kills every fleeing bacterium mid-phase, `destroyed_count` alone
  reaches `spawn_count` before finish has pushed the roster and cleared the
  phase.
- A killed fleeing bacterium does not return, so an escape is not guaranteed at
  crossing. The roster's build-up/flush rhythm depends on the player denying
  escapes.
- The zero-duration phase makes 1.3 behave as an immediate flee while leaving one
  insertion point for the eventual animation.
- The animation itself is presentation only and must not decide anything.

## Flee threshold

### Decision

Each wave draws its flee threshold once, at spawn, from
`derive_seed(wave_seed, .Level, 0)`. The threshold is a per-mille integer
fraction **destroyed**, not a fraction remaining. The crossing test is
`destroyed * 1000 >= spawn_count * threshold_permille`, all integer: no
division, no float compare, no boundary rounding. The rolled value is the **base**
threshold; "Flee threshold scaling" defines the effective value the crossing test
actually uses.

The curve is a half cycle of a raised cosine over 20 levels:

```
t = clamp((level - 1) / 20, 0, 1)
base = 500 + 225 * (1 + cos(pi * t))
```

A per-wave spread of ±50 is drawn around the base, then the result is clamped to
`[500, 1000]`.

The threshold was assign-and-display only before wave resolution. The crossing
test now lands in Phase 1.2 alongside wave-membership tracking; the flee response
lands in Phase 1.3.

### Reason

Direction was the whole problem. The old `WaveParams.threshold = 0.8` was
ambiguous between "flee at 80% destroyed" and "flee while 80% alive"; read as
fraction remaining, it inverts the difficulty. Naming the quantity *destroyed*
and storing per-mille makes the value unambiguous and diffable in logs, which is
how the seeding work is verified.

The curve is flat at both ends and steepest mid-curve, so early levels stay
predictable and the middle of the run moves fastest. Two separate bounds do
different jobs: 500 is the chosen floor, and 1000 is what keeps the value
crossable.

The spread is applied before the clamp. `base + spread` peaks at exactly 1000 at
level 1, so the upper bound is exactly sufficient and the spread stays symmetric
everywhere. A lower upper bound would truncate the positive half of the draw at
early levels and make the coin flip one-sided.

### Consequences

- One independent draw per wave, so waves within a level differ from each other
  rather than sharing a level-wide value.
- The 500 floor and the `/20` span were picked for shape, not balance, and are
  expected to be tuned in play.
- `WaveParams.threshold` has been removed; the seed is the only source.
- The spread is the inclusive range ±50, matching the decision text above. The
  earlier `[-50, 49]` behaviour is superseded by "Range semantics".
- Per-wave sizes are roughly 3–6 under the budget split, so one kill is
  167–333 permille and crossings are coarse. The old table written against
  `3 + level*2` per wave is superseded and removed; the curve's shape is
  unchanged.
- At level 15 the threshold is around 593 permille, so a five-bacterium wave
  flees with roughly two still standing.
- A level marked `flee_prohibited` skips the threshold draw entirely and uses
  `1000`. The flag has no CLI or menu surface in 1.3; it is verified by a
  temporary code edit and becomes a boss-level setting in Phase 8.

## Flee threshold scaling

### Decision

The effective threshold is the rolled base plus a per-buff increase, using the
highest buff count among the wave's active owners:

```
effective = clamp(base + 50 * max_buff_count, 500, 1000)
```

The increase is evaluated at the crossing test, not stored. With no buffed
bacteria it equals the base. If the highest-buffed bacterium dies, the effective
threshold drops on the next frame. The `50` is provisional.

### Reason

This keeps the threshold a wave-level decision while making a carried bacterium
fight harder before escaping. Using the highest count rather than the average
prevents one veteran from being diluted by fresh bacteria. Recomputing at the
crossing test means killing the resistance source makes the rest easier to rout.

### Consequences

- A single heavily buffed bacterium anchors the whole wave's flee point.
- The overlay's threshold value is the rolled base unless it is extended to show
  the effective value; logs should carry both.
- The `50` is a tuning constant, not a base-stat value, and can change without
  changing the roster or buff model.
- This resolves the open question: the flee threshold does scale with buff count.

## Resistance buffs

### Decision

Fleeing bacteria gain resistance buffs on return. Buffs are per-instance, held in
a fixed-size array of **5** slots on `BacteriaCold`. Each escape rolls a category
from the full set, so repeats are allowed by design. The roll happens at the flee
event and is stored in the roster entry; it is applied when the bacterium returns.
If all five slots are filled, the new buff replaces the oldest.

Categories for v1, one per axis: **Hardy** (+max health), **Resistant** (reduced
damage taken), **Biofilm** (absorbs the first N hits), **Frenzied** (+speed).

A returning bacterium keeps its identity and species. Health is restored to spawn
max, which may itself be buff-boosted.

### Reason

Resistance is the correct model for bacteria under pressure, and it keeps species
definitions immutable. Five slots is enough to feel consequential while remaining
a fixed compile-time constant, which suits the existing SoA layout — buff data
cannot live in `BACTERIA_DEFS`, since that is a `const` array indexed by species and
buffs vary per individual.

Rolling from the full set rather than excluding held categories was chosen for
simplicity and for greater variance in resulting stacks.

### Consequences

- **Buffs live on the bacteria instance**, not in `BACTERIA_DEFS`.
- **The roll is stored on the roster entry.** A pending bacterium is self-contained:
  species, buffs, and its return delay. Dropping an entry does not need a later
  roll to be undone.
- **Buff rolls are seeded.** The roll derives from a stored `Wave.seed` through a
  new `.Buff` seed category and the fleeing slot index. A wave flees once, so the
  slot index is unique within that roll.
- **The roll is taken at flee begin.** The escaping pool slot carries the new
  buff for the duration of the phase, and `wave_flee_finish` copies it into the
  roster entry. A bacterium killed during the phase discards that roll with its
  slot; nothing needs undoing.
- **Phase 1.3 owns the scaffolding.** It adds the category enum, the five-slot
  array, `BUFF_DEFS`, and the seeded roll because the flee response needs them.
  Phase 1.4 applies the four effects and wires `species_unlocked` into spawning
  (both landed).
- **Each escape is a compounding gain**: a buff plus a free full-health restore,
  while the rest of the wave stays at spawn baseline. Failure makes the game
  harder, which is thematically intended. The array never grows past five; a sixth
  escape replaces the oldest. Boss levels are the eventual hard clear, not the
  thing that enforces the slot count. Growth is additive within a category and
  bounded by that category's ceiling (see "Buff magnitude scaling").
- **The specific runaway risk is Frenzied stacking.** A 5-stack Frenzied
  Pseudomonas at base speed 400, multiplied by a wave `speed_scalar` that already
  scales with level block (`src/procedural.odin:132`), could produce an
  unplayable screen. The additive-with-cap rule bounds this; the ceiling is still
  a tuning value.
- **`Resistant` has no weapon-weakness interaction.** Weapon weakness was removed
  (see "Weapon weakness removed"); damage is one number per weapon. Resistant
  reduces that number with a floor that keeps the bacterium killable.
- **Magnitudes are percentages, not absolute values**, per "Buff magnitude
  scaling". The earlier rule — absolute values in `BUFF_DEFS`, deliberately not
  derived from `BACTERIA_DEFS` — is superseded. A percentage is an explicit
  design multiplier, not a silent rescaling driven by later base-stat changes.
- Buffs need a visual tell, or the player cannot learn to prioritize. Species color
  already carries identity (`r/g/b` per species, all four 16x16 with distinct
  colors), so the buff visual needs its own channel rather than competing for
  color.

### Open questions (not yet decided)

- **What visual channel do buffs use?** One outline per category is the current
  leaning, held loosely. Does not need resolving before the skill tree.

## Buff storage representation

### Decision

Buffs are stored per instance as `[MAX_BUFFS]BuffInstance` plus a `buff_count`.
Each `BuffInstance` holds a `BuffCategory` and the rolled magnitude, stored as a
permille fraction of that category's ceiling in `BUFF_DEFS`. Slots stay in
chronological order. When all five are filled, a new buff shifts slots 1–4 down
and is written at index 4, so index 0 is always the oldest.

`max_health` lives on `BacteriaHot`, beside `health`.

### Reason

The magnitude varies per escape — level scaling and the lucky/unlucky range make
it instance data, not a table lookup. Storing it with the category keeps the
append and shift atomic and makes a roster entry self-contained. `BUFF_DEFS`
retains the per-category ceiling and unit, so tuning still has one anchor.
Chronological order makes logs and any later display read naturally; with five
slots the shift cost is irrelevant. `max_health` is combat state, so it belongs
with `health` rather than with the buff list.

### Consequences

- `bacteria_buff_add` is the append path for a new escape. Restoring a roster
  entry must copy the whole array and count, not call the append helper once per
  buff, or the slots shift again.
- `bacteria_init` clears buffs before a spawn path can copy stored buffs onto a
  reused slot. Any future spawn-params buffs must be applied after that clear.
- `max_health` is base health in 1.3. The return path must compute the buffed
  value before restoring health, otherwise Hardy bacteria return at base health.
- `BuffInstance` carries both category and magnitude. Restoring a roster entry
  copies the whole array; `bacteria_buff_add` shifts whole instances, never
  categories alone.
- The total cap is applied at read time by `buff_total(cold, category)`, not at
  roll time. A sixth escape still replaces the oldest slot; the cap only decides
  how much of the new stack actually counts.
- The `BuffCategory` ordinal is part of a seeded roll once the flee path indexes
  the enum. The order is frozen as `Hardy, Resistant, Biofilm, Frenzied`.
- `Hardy` is ordinal zero, so unused slots past `buff_count` read as `Hardy`.
  Every consumer iterates to `buff_count` only; a full-array loop would silently
  apply Hardy buffs.

## Weapon weakness removed

### Decision

Weapon weakness matching is removed. `WeaponDefinition` carries one `damage`
value instead of effective / neutral / ineffective tiers, and
`BacteriaDefinition.weakness` is deleted. `WeaponType` remains as identity — it
indexes the weapon texture arrays, `Player.current_ammo`, `Bullets.weapon_type`,
and `WEAPON_DEFS`.

The player starts with Neutral. PCN and PMX are unlocked through the skill tree,
which also grants active abilities and passive stat nodes. Until that tree exists,
the player only ever fires Neutral; no switching control is added in Phase 1.

Weapons will be differentiated by a damage-versus-fire-rate tradeoff: some faster
and weaker, others slower and stronger. Current single damage values are
placeholders; tuning belongs to Phase 7.

### Reason

The weakness system could not be made to work in play. Keeping a mechanic that
does not function adds branching to the damage path without adding a decision the
player can meaningfully make. Moving unlocks to the skill tree gives weapons
progression without requiring every weapon to have a matching bacteria weakness.

### Consequences

- `calculate_bullet_damage` is deleted; the collision path applies a single
  weapon damage value, then resistance buffs.
- The `bacteria_def` local in `collision_update` becomes unused and must be
  removed with the damage call, or it becomes a new vet finding.
- PCN and PMX are stat-identical placeholders (different textures only) until
  Phase 7 tunes their speed and damage tradeoff.
- `PROJECT.md`'s claim that weapon selection was implemented was wrong: no key
  changes `current_ammo`. Corrected to match the code.
- Weapon progression is entirely owned by Phase 7. If that phase slips, there is
  no weapon variety in the meantime.
- Resistant no longer has a weakness interaction to resolve; that open question
  is closed.

## Buff magnitude scaling

### Decision

Every buff roll produces a **normalized fraction** in permille of a per-category
ceiling. `BUFF_DEFS` stores that ceiling (`max_magnitude`) in the category's own
unit: Hardy in percent of base health, Resistant in permille damage reduction,
Biofilm in hit count, Frenzied in percent of base speed.

The fraction's range depends on the 5-level block from "Early-level determinism":

| block | levels | fraction (permille of ceiling) | Hardy equivalent |
|-------+--------+-------------------------------+------------------|
|     0 |    1–5 |                         20–40 |         10–20%   |
|     1 |   6–10 |                       100–200 |        50–100%   |
|     2 |  11–15 |                       200–400 |       100–200%   |
|     3 |  16–20 |                       300–600 |       150–300%   |
|    4+ |   21+  |                      500–1000 |       250–500%   |

The table is a starting proposal, not balance. Tuning changes the numbers, not
the mechanism.

The total magnitude for a category across all of a bacterium's slots is clamped
to that category's ceiling. Stacking is additive-with-cap, never free
multiplication. Biofilm floors at one hit so an early roll is meaningful.

Both the category and the fraction are rolled at flee begin from the existing
per-slot RNG (`derive_seed(wave.seed, .Buff, slot_index)`), category first, then
fraction. The draw order is part of the seeded contract.

### Reason

The design goal is that early escapes are a small bonus and late escapes can be
enormous, with a seeded lucky/unlucky spread inside each band. A single normalized
curve gives every category the same shape while keeping its own unit, so tuning
lives in one table plus one band table.

Additive-with-cap answers the Frenzied stacking question and bounds the
`speed_scalar` compounding. A per-category cap is the only coherent reading:
health percent, damage permille, hit count, and speed percent cannot share one
number.

The earlier absolute-value rule is superseded. Its reason was to avoid silent
rescaling when base stats change; a percentage is a deliberate multiplier, and
level scaling requires a per-roll value that cannot be a static table entry.

### Consequences

- `BuffDefinition.magnitude` becomes `max_magnitude`; `BuffInstance` stores the
  rolled fraction, so the effective magnitude is computed at the application
  site.
- The cap is enforced at read time in one helper used by all four effect sites;
  a sixth escape still replaces the oldest slot, the cap only decides how much
  counts.
- Hardy and Frenzied apply in `bacteria_init`; Resistant and Biofilm apply at the
  damage site. `max_health` must be computed before health is restored.
- The category remains the first draw from the per-slot RNG, so existing category
  rolls are unchanged; the fraction is a new second draw.
- The flee threshold's `+50 * max_buff_count` is a separate mechanism and stays
  flat and count-based. Scaling both at once would make tuning uninterpretable.
- Level 1–5 buffs stay small by construction, matching early-level determinism.

## Bacteria identity and behavior

### Decision

Separate species identity from reusable gameplay behavior. A species defines
what a bacterium is; its behavior configuration defines what it does. Behaviors
should be composed from reusable categories rather than implemented as a separate
bespoke behavior for every species.

The initial categories are:

- Movement — e.g. straight, sine, zigzag, scatter, sweep
- Attack — e.g. basic, charge, ranged, spawn
- Defense — e.g. normal, armored, resistant
- Group — e.g. none, swarm, protect
- Lifecycle — e.g. normal, split, spore, reposition

These are design categories, not a commitment to implement every example. Start
by refactoring the existing four species to use the model before adding more
species or expanding the behavior set.

### Reason

Species-specific behavior branching does not scale well as the roster grows.
With 10–15 species, putting each species' unique rules into multiple switches
would spread species knowledge throughout the code and make combinations hard to
reason about.

Separating identity from behavior allows species to share capabilities and makes
encounter composition more expressive: procedural generation can eventually
choose species, formations, entry patterns, and compatible behavior combinations
without requiring every combination to have its own implementation.

This also preserves the decision that bacteria never change species. A returning
bacterium keeps its species identity and instance-specific resistance buffs;
those are separate from its reusable behavior configuration.

### Consequences

- Keep species definitions as the source of species identity and base properties.
  Do not make each species synonymous with one bespoke movement implementation.
- Implement behavior categories as reusable building blocks, and compose species
  from the behaviors they need. Avoid adding categories without a concrete
  gameplay use.
- Refactor the existing Strep, Staph, E. coli, and Pseudomonas behaviors first.
  Use those species to validate the architecture before adding more bacteria.
- Keep per-instance state (health, current behavior state, wave membership, and
  buffs) separate from species definitions and reusable behavior configuration.
- The behavior architecture is deferred until the current level/wave lifecycle
  slice is complete and verified. Do not interrupt the current slice to redesign
  the enemy system.
- Once the architecture is established, new species can be added by composing
  existing behaviors where possible; genuinely new behavior should be introduced
  only when it creates a distinct gameplay role.
- Behavior and procedural composition must preserve seeded determinism. Any
  random choices that affect generated behavior must use the project's seed
  derivation rules, not wall-clock time.
- Adaptive wave composition remains separate deferred work, as recorded in
  "Fleeing and returning". Choosing encounters based on what the player is not
  killing still requires a kill-count system.

## Determinism

### Decision

Determinism means **deterministic decisions with continuous motion** — reading C
from the three options considered.

Concretely, two separate clocks:

- A **tick counter** that increments by a fixed amount each update. Every decision
  and every branch point reads this.
- **Real elapsed time**, used only for how far things move. Never for decisions.

No decision may read wall-clock time. A decision may depend on continuous motion
only when that motion is itself tick-driven.

Recorded input replay is explicitly **not** in scope. If that need ever arises, it
is a tooling decision to make when the first such test is written, not an
architecture decision made now.

### Reason

Three readings of "same seed, same results" were considered:

- **A — generated content identical.** Nearly free; already true of the
  generation code, which derives everything from `derive_seed` at init before any
  player input exists. Does not make gameplay debuggable.
- **B — full run identical including outcomes.** Requires recorded input, a fixed
  timestep, and bit-exact float determinism maintained indefinitely. Delivers a
  regression-testing tool, not a player-facing feature.
- **C — deterministic decisions, continuous motion.** Keeps A's guarantee, and
  makes replay debuggable: a bug report about a level 7 wave 3 flee threshold can
  be reproduced exactly, because thresholds and waves are identical even though
  the player's kills may differ.

C was chosen as the only reading that both holds the determinism guarantee and
stays achievable for an interactive game. B was rejected because a human player
could never observe it without replaying a recorded input stream, and because it
demands float-exact discipline forever.

Note that `PROJECT.md` already scopes this correctly: it asks for *"fun,
deterministic enemy waves"* — waves, not runs.

### Consequences

- **Progress.** The clock split has landed: the main loop is the only wall-clock
  reader, and it emits a 60 Hz tick count (`TICK_RATE`, clamped to
  `MAX_TICKS_PER_FRAME` with the excess dropped). Wave spawn and dive timers, the
  level transition, `flee_start_tick`, and `formation_complete_tick` all read that
  clock; `delta_time` now feeds motion only. Of the three original violations,
  two remain:
  - The dive gate still compares `sdl.GetTicks()` against
    `formation_complete_tick` — a mixed-unit leftover that remains always true.
    It is scheduled for removal, not conversion.
  - `formation_complete` is still derived from continuous entry motion and must
    become tick-driven.
  See `docs/plans/2-determinism.md` for the step split.
- **`formation_complete` is the one real threat to this rule.** It is a decision
  derived from continuous motion: whether every bacterium has finished its entry
  path depends on accumulated time, so it could land on different ticks across
  runs and diverge everything downstream. It must become tick-driven. The rule's
  third clause exists specifically to forbid this coupling.
- **Two alternatives were rejected.** Fixed timestep throughout the main loop is
  the textbook answer but changes game feel, which is not worth paying for yet.
  Making the decision unconditioned on motion (a seeded fixed delay) is cheapest
  but decouples the fiction — the formation could "complete" while bacteria are
  visibly still in flight.
- **Scope:** this decision is recorded now so later work does not violate it. The
  `delta_time` refactor itself is tracked separately from level advancement,
  because mixing a timing refactor into an advancement slice makes both harder to
  verify independently. The door is left open for fixed timestep later — it becomes
  a small change under this model, not a rewrite.
- **Verification means "generate twice, compare," plus "same branch events."** It
  does not mean identical runs. Identical *flee behavior* is untestable with a
  human at the controls and should not be asserted.
- **Seed sensitivity is separate from determinism.** "Same seed, same run" is the
  contract; how much the run changes when the *seed* changes is a feel decision.
  Early levels are deliberately near-insensitive to the seed and later levels are
  not (see "Early-level determinism"). This does not weaken the contract.

### Resolved

The flee threshold direction is settled: a per-mille fraction **destroyed**, drawn
once per wave from `derive_seed(wave_seed, .Level, 0)`. The old
`WaveParams.threshold = 0.8` was ambiguous between fraction killed and fraction
remaining and has been removed, so the seed is the only source of a threshold.
See "Flee threshold".

## Frame pacing

### Decision

Vsync is enabled by default and is the game's normal frame pacer. `--vsync
<true|false>` controls it explicitly; the old `--no-vsync` flag is replaced.

When vsync is off, a software limiter paces the loop at `--fps`, default **60**.
`--fps 0` disables the limiter, so a no-vsync run spins unbounded again. With
vsync on, `--fps` has no effect.

The limiter uses a deadline accumulator, not a fixed sleep: each frame advances
`next_deadline` by `1000 / fps`, sleeps only for the whole milliseconds remaining,
and resets the deadline to now when a frame overruns. It runs after
`RenderPresent`.

### Reason

`--no-vsync` was parsed and advertised but never read: `RENDERER_FLAGS` always
included `PRESENTVSYNC` (`src/game.odin:17`), so the renderer was never actually
vsync-free and the flag did nothing. Replacing it with an explicit boolean makes
the setting honest and lets a test run turn vsync off without a source edit.

With vsync genuinely off, the loop has no upper bound. Some players turn vsync off
deliberately; without a replacement pacer they get an unbounded loop. Two things
follow. CPU use is unbounded for no visual benefit. And because `delta_time` comes
from `GetTicks()` at millisecond resolution (`src/game.odin:547-548`), many frames
compute `delta_time == 0`, so motion stalls on those frames instead of advancing.
A 60 fps default restores a sane cadence and matches the rate the game is tuned
against.

The cap applies only when vsync is off, so a vsync'd run on a 120/144 Hz display
keeps the monitor's rate. A deadline accumulator was chosen over sleeping the
remaining frame budget because truncation and late wakes accumulate as drift;
deadline accounting keeps the average rate correct without catch-up bursts.

### Consequences

- `config.no_vsync` becomes `config.vsync`, defaulting to `true`; the CLI shape
  is `--vsync <true|false>`, space-separated and parsed with
  `strconv.parse_bool`.
- `--fps` is silently ignored when vsync is on, and `--help` says so. It is not
  an error, so a saved command line still works if vsync is flipped.
- `--fps 0` restores the unbounded loop deliberately. It is a testing value, not
  a supported play mode.
- The limiter is pacing, not determinism. It does not supply the fixed tick
  counter and does not make any decision reproducible. See "Determinism".
- `delta_time` keeps its source and resolution. Capping removes most zero-length
  frames but does not make them structurally impossible; that is the tick work.
- "Vsync unavailable" is not detected. The limiter keys strictly off
  `config.vsync`; if a driver ignores `PRESENTVSYNC`, the loop still relies on
  it.
- 60 is a default, not a hard design rule. Changing the target is a CLI concern,
  not a gameplay decision.
- The options are eventually exposed in a settings menu. Until that exists, the
  CLI flags are both the testing path and the only path. The limiter must read
  `config.fps` live rather than caching the target at startup, or a menu change
  will not take effect until restart.

### Open questions (not yet decided)

- **Settings precedence.** Once a settings menu persists vsync and the FPS cap,
  does a CLI flag override the saved value for that run, or write through to it?
  The usual answer is defaults < saved < CLI, session-only, but it is not
  decided.
- **Runtime vsync failure.** `SDL_RenderSetVSync` can fail on some backends. Is
  the fallback a restart prompt, or a renderer recreation that re-inits assets?
- **Menu structure.** A settings page is either a mode inside `.Menu` or a new
  `GameState`. `.Menu` currently owns only a title and a hint, and the skill tree
  is already promised `Level_Transition`, so the two should not compete for the
  same mount point.

## State machine

### Decision

`Level_Transition` is a real state that does real work, and it is the designated
mount point for the skill tree when that system is built.

### Reason

The skill tree is deliberately deferred until level advancement, procgen, and
formation generation are solid. Building the transition state now means the later
skill tree mounts into an existing state rather than requiring a rewrite.

### Consequences

- The transition state must own level progression: deriving the next level's seed,
  drawing its wave count, initializing its waves, and resetting per-level state.
  It is the single place level advancement happens.
- It must have observable behavior now — hold the frame, display the level number,
  advance. A transition state with no output is dead code that reads like a
  feature, is hard to test, and is easy to leave broken.
- Note the tension: mounting the future skill tree here was chosen deliberately
  over a purely cosmetic transition, accepting some speculative structure in
  exchange for a clean integration point later.

## Seeding

### Decision

Add `.Level` to the existing `SeedCategory` enum rather than reusing `.Wave`
with a distinguishing number. Add `.Buff` for the per-escape resistance roll, so
buff rolls do not overload `.Enemy` when species choice is wired later.

Derive seeds by **chaining**, not by a single global counter: a level derives from
the run seed by level number, and each wave derives from its level seed by its
index within that level.

### Reason

Self-documenting, and avoids overloading an existing category with a second
meaning.

A global monotonic wave number was considered and rejected. It requires cumulative
state threaded through level transition, and to number level 9's waves you must
already know how many waves levels 1-8 drew — which are themselves seeded draws.
That makes a wave's seed depend on run history rather than on its position, and
draws a level's wave count before any wave can be named.

Chaining satisfies the same uniqueness requirement with no accumulated state, and
keeps the invariant checkable locally: every `(parent, category, number)` triple
appears once.

### Consequences

- The uniqueness invariant is **per parent**, not global. No `(parent_seed,
  category, number)` triple may be reached twice in a run; the same
  `(category, number)` under a different parent is fine. This replaces the earlier
  requirement that `(category, number)` be unique across a full run, which chaining
  makes both unnecessary and misleading.
- `level_init` must draw the level's wave count *before* initializing any wave.
  The loop index is the wave index.
- `level_seed` carries per-level decisions, `wave_seed` carries per-wave ones. The
  flee threshold is `derive_seed(wave_seed, .Level, 0)` rather than a `.Level`
  number on the level seed, so no `.Level` number's meaning depends on how many
  waves a level happened to draw.
- A wave seed is a pure function of `(run seed, level, wave index)` and can be
  recomputed without simulating anything. It must be stored on `Wave` because the
  flee-time buff roll happens after `wave_init` has returned.
- `.Level` no longer means "level number" below the root derivation; it is reused
  for per-level draws with small numbers. A second category would restore strict
  meaning but is not worth it at this call count.
- Same seed in, same run out.
- `master_seed` lives on `World`, not `Game`. The transition path and
  `Level_Transition` both need to derive seeds and only see `World`. Selection —
  fixed from `--seed` or clock-derived — still happens once, in `game_init`, and
  must be written before `world_init` runs.
- The derivation graph has **eight** distinct `(parent, category, number)` triples
  in a run:
  - `(master_seed, .Level, level_number)` → `level_seed`
  - `(level_seed, .Level, 0)` → the level's wave count
  - `(level_seed, .Wave, i)` → `wave_seed`
  - `(wave_seed, .Entry, 0)` → entry points
  - `(wave_seed, .Level, 0)` → flee threshold
  - `(wave_seed, .Wave, 0)` → count jitter
  - `(wave_seed, .Wave, 1 + spawn_index)` → fresh-spawn species (added with
    species variety in 1.4; the `+1` keeps it clear of the jitter triple)
  - `(wave_seed, .Buff, slot_index)` → the buff for a bacterium fleeing from
    that wave
- The species triple is re-derived on a failed spawn retry: `wave_update` returns
  before advancing `spawn_index`, so the next spawn tick reaches the same triple
  again. This is harmless because `derive_seed` is a pure function — the retry
  produces the same species — but it means the uniqueness invariant is about
  *purpose*, not byte-level call count: no triple may be used for two different
  generated values. A literal "never reached twice" reading is violated by the
  retry.
- The buff triple is keyed by the fleeing bacterium's slot. A wave flees once, so
  each slot is used at most once per wave; a bacterium that returns and flees
  again does so under the new wave's seed.
- Index bases: level number is 1-based and player-facing, matching
  `level_to_params`. Wave index is 0-based and internal, matching
  `level.wave[i]`. Mixing them is how a level silently wraps to the wrong block.

## Scope

### Decision

The next slice covers level advancement *and* a minimal menu, rather than level
advancement alone.

### Reason

Level advancement cannot be observed or verified without a way to reach
`.Playing`. Currently `world.state` is set to `.Menu` and never changed, and the
main loop ignores `world.state` entirely, updating every system unconditionally.

### Consequences

- State gating in the main loop is a prerequisite of this slice, not optional
  polish.
- "Minimal menu" means only enough to start the game: state gating, an entry
  action, and a visible hint. A full menu — options, quit confirmation, and so on
  — is separate work.
- Every `GameState` variant should be reachable except `.Game_Over`, which has no
  trigger: the player has no health field, nothing detects player-bacteria
  collision, and no damage is applied to the player. Making it reachable would
  mean inventing a death condition, which is a design decision rather than
  cleanup. It stays a deliberate dead enum value until that decision is made.

## Menu and debug entry

### Decision

`.Menu` renders **only** the menu. The world is not drawn behind it. Today that is
a title and a keybind hint; the intent is full-screen art behind the same clear
later.

`level_init` runs in `world_init`, before any state transition, so the menu phase
does not generate a level in response to input. Enter is a bare state flip.

`--debug` starts directly in `.Playing` with the debug overlay enabled, skipping
the menu.

### Reason

Drawing the menu over a generated world would make the menu's contents depend on
whether a level already exists, and would show a level the player has not opted
into. Keeping the menu self-contained means `render_menu` owns its own clear and
its own output, and becomes purely a matter of adding art.

`level_init` having exactly one call site is worth more than the purity of
"nothing exists before the player starts". A second call site for the debug path
would be the kind of duplication that drifts — it already caused `--level` to be
silently dropped once.

### Consequences

- `render_state` must handle `.Menu` separately from the world-rendering states.
  Empty cases are not acceptable: `.Menu` previously fell through with no clear,
  which smears the previous frame rather than showing a blank screen.
- The level exists while `.Menu` is displayed; it is simply not drawn or updated.
  This is harmless while nothing observes it.
- `--debug` is a development convenience and does not define a gameplay rule. If
  it ever conflicts with a real startup path, the real path wins.
- `Level_Transition` is the owner of level progression. `world_init` holds the
  only initial generation and the transition holds all later ones; the "one
  call site" rule applies per path, not per program.

## Sequencing

### Decision

Level advancement, procgen, and formation generation will be nailed down before
the skill tree is added.

### Reason

The skill tree is a large independent system — node graph, persistence across
levels, UI, stat application — and building it against unstable underlying
systems risks rework.

### Consequences

- `ARCHITECTURE.md`'s skill tree is committed *intent*, not a speculative idea,
  but it is not next.
- Wave cadence and formation variety are scheduled as Phase 3A, after Phase 3
  (frame pacing) and before Phase 6 (enemy behavior) and Phase 7 (skill tree).
  Tuning before frame pacing would need re-tuning; the handoff seam must exist
  before the flee phase gains animation duration.
- The boss meter and boss fights described in `ARCHITECTURE.md` are also deferred.
  Their interaction with fleeing-driven difficulty is an open question: two
  escalating systems can stack multiplicatively and quietly break difficulty
  tuning, so this should be decided before tuning begins.

## Vet review cadence

### Decision

A vet review runs at the end of each top-level phase in `ROADMAP.org`, not after
each numbered step within a phase. Each phase carries one gate: run
`odin check src -vet` and resolve every finding before the phase is verified.

### Reason

`-vet` catches dead declarations left behind by refactors and stubs, not logic
bugs. Running it after every small step would turn normal in-progress leftovers
into blockers and slow iteration; running it never lets scaffolding accumulate.
The phase boundary is already the project's verification boundary — "a phase
starts when the one before it is verified" — so attaching the gate there adds no
new cadence.

### Consequences

- Phase 1's gate is step 1.8, after the unit tests, not a check after each of
  1.1 through 1.7. Phases 2–11 each carry a final checkbox item.
- A phase is not verified while vet is dirty. The gate is a cleanup obligation,
  not a claim about gameplay correctness; behavioral verification stays with
  the phase's own tasks.
- Vet work found mid-phase is deferred to that phase's gate. This supersedes
  folding vet cleanup into an individual step such as 1.3.
- The gate names `odin check src -vet` explicitly. If a `make vet` target is
  added later, the gate text should point at it.

## Wave pressure

### Decision

Difficulty is measured by **peak simultaneous enemies**, not by total level
budget or average per-wave size. Each level's peak must be non-decreasing as
levels rise. The budget stays `3 + level*2` and is split across waves under
"Enemy counts"; the drawn wave count is constrained so a rising budget cannot
produce a smaller peak.

### Reason

Level 1 fields five enemies in one wave. Level 2 draws one or two waves under a
budget of seven; the two-wave case splits into four and three, so the largest
cluster the player sees drops from five to four. The budget rose while the
pressure fell, which is the opposite of the intended ramp. Average share is a
poor proxy for what the player feels.

### Consequences

- Wave count stays a seeded draw. Only its bound is constrained, so no run
  history enters wave seeding and level 1's one-wave-of-five shape survives.
- A bound alone is not enough if waves stay sequential: the next wave cannot
  begin before the current one clears, so peak pressure still drops at the
  handoff. This decision depends on "Wave handoff".
- Flee thresholds and buff scaling are untouched. Peak pressure is a generation
  invariant, not a combat rule.

## Wave handoff

### Decision

The next wave begins spawning while the current wave is still resolving. A wave
still ends only when all of its own members resolve, never on a timer; what
changes is that resolution of one wave is no longer a global gate on the next
wave's spawn. The next wave may overlap the current wave's flee phase.

### Reason

Today the last kill of wave N is followed by wave N+1's full `spawn_delay`
before its first spawn, so there is an idle gap between waves. The player asked
for no break. The gap would grow when Phase 6 gives the flee phase duration and
exit motion, because advancement already waits for that phase.

### Consequences

- `wave_index` is no longer the sole authority for which wave is active. A
  bounded active window is needed in `world_update`; the exact size is a tuning
  choice for step 3A.1.
- Ownership is already carried on the bacterium by wave index, so multiple
  active waves need no new identity field or composite key.
- The roster tick still fires once per wave completion, not once per frame.
- Level end still requires every wave to resolve. Overlap changes when a wave
  starts, not when the level ends.
- Phase 6 adds duration and motion to the flee phase only. It must not become a
  gate on the next wave's first spawn, or it restores the gap this decision
  removes.

## Formation position and species

### Decision

"Front" means closer to the player, not earlier in spawn order. Species
placement is a bias by formation slot class: certain species are more likely in
front slots and others behind. A returning bacterium keeps its species and is
assigned to the slot class matching that species.

### Reason

The player wants some bacteria predominantly in front and others behind, and
wants the mix to feel composed rather than drawn per spawn index. Keeping the
class rule for returners preserves the settled decision that bacteria never
change species while still making placement meaningful for them.

### Consequences

- Species choice moves from the spawn-index draw in `wave_update` to a
  position-aware assignment. This changes the purpose of the
  `(wave_seed, .Wave, 1 + spawn_index)` triple in "Seeding"; that section must be
  updated when step 3A.4 lands.
- Returners keep their species and their resistance buffs; only their slot class
  is chosen by the same rule as fresh spawns.
- The per-species class mapping, and whether the bias is a hard rule or a
  weighted tendency, are still open. They are tracked in ROADMAP.org's "Before
  starting: open decisions" and must be settled before 3A.4.
- The decision applies to generation only. It does not change entry, hold, dive,
  or return motion, which Phase 6 owns.
