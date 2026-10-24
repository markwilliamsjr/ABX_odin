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
- `PROJECT.md`'s "Current Systems" is the only document claiming systems exist,
  so it is the one that most needs an explicit label. It currently has none.
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
- The threshold table in `ROADMAP.org` must be re-derived. The threshold remains
  scale-free (a per-mille fraction destroyed), but at 3–6 enemies one kill is
  167–333 permille, so crossings are coarse.

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

The jitter draw still runs every wave even when its band is 0, and the wave-count
draw still runs at level 1 even though its range has collapsed to a single value.

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
  900–1000, but that is unobservable: a five-enemy wave crosses every threshold in
  that band only at full destruction.
- The seed graph is unchanged. Degenerate draws still consume their triples,
  following the `MAX_WAVES` saturation precedent.
- The floor/budget overrun is confined to levels 4, 6 and 7.
- Level 5 to 6 has a structural discontinuity: the maximum rises 4 to 6 while the
  minimum jumps 1 to 3. It is inherited from block-based ranges, not introduced by
  the ramp.
- If formation regions ever multiply, the pinned entry slice must hold at least
  `region_count` points, or `generate_entry_points` returns `ok = false`.
- Later variance sources (formation variety, species choice) should be gated by
  level the same way, so the opening does not drift back toward generated.

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
- `species_unlocked` (`src/procedural.odin:124`, computed but never read) is
  still to be wired, but for **spawn variety**, not promotion.
  `bacteria_spawn` currently hardcodes `.Strep` (`src/level.odin:128`), so the
  game is one species throughout.

## Return scope

### Decision

The pending roster lives on `World` and **survives level transitions**.

A bacterium that flees enters the queue and appears in the **next wave** — read as
a queue position, not a per-level dump. If it flees again, it enters the wave
after that. A level therefore never opens with a flood; the backlog arrives one
wave at a time.

Carried bacteria **may flee again**, rolling a fresh buff and receiving a fresh
health restore each time. There is no escape counter.

At a **boss level, all bacteria must be destroyed** before the player can advance.
Bosses are the pressure valve for the roster: fleeing is not permitted there, so a
fully-stacked bacterium must finally be killed. The roster can therefore never
exceed the 5 buff slots, and it only clears at a boss.

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

Disabling fleeing at boss levels also dissolves a problem that otherwise needs its
own rule: what happens when a bacterium with a full roster of 5 buffs escapes a
sixth time. No slot-replacement or discard rule is needed, because the cap can
never be exceeded.

### Consequences

- The roster lives on `World`, not `Level`. `Level_Transition` must **not** clear
  it — a change to what that state does when resetting per-level state.
- **No escape counter** exists on a bacterium. The 5-slot cap is load-bearing, not
  merely a safety bound.
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

- **Does the flee threshold scale with buff count?** A carried bacterium returns
  at full health with up to 5 buffs. If it can flee the instant the threshold is
  crossed, a heavily buffed bacterium barely participates, and the buff system
  feels pointless — the player earns the escalation and gets nothing from it.
  Suggestion: a stacked bacterium should fight harder before escaping.
- **At boss levels, is fleeing disabled outright, or permitted but buff-free?**
  Only "disabled" makes "clear all bacteria" mean what it says.
- **Does the roster enter the boss level, or is it spent first?** Letting it arrive
  means the boss level is the hardest thing in the game by design — the player
  brings their worst case and must finally kill it. This appears dramatically
  stronger than flushing beforehand, but it is unconfirmed.
- **Boss shape.** Separate level, or special wave within a level? If a special
  wave, the other waves in that level follow normal flee rules.

## Resistance buffs

### Decision

Fleeing bacteria gain resistance buffs on return. Buffs are per-instance, held in
a fixed-size array of **5** slots on `BacteriaCold`. Each escape rolls a category
from the full set, so repeats are allowed by design.

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
- **Each escape is a compounding gain**: a buff plus a free full-health restore,
  while the rest of the wave stays at spawn baseline. Failure makes the game
  harder, which is thematically intended, but growth is multiplicative rather than
  additive. The 5-slot cap is the bound, and because carried bacteria can be
  escaped on indefinitely, that cap is load-bearing rather than merely a safety
  net. Boss levels are what keep it from being exceeded.
- **The specific runaway risk is Frenzied stacking.** A 5-stack Frenzied
  Pseudomonas at base speed 400, multiplied by a wave `speed_scalar` that already
  scales with level block (`src/procedural.odin:132`), could produce an
  unplayable screen.
- **`Resistant` interacts with the weapon weakness system.** Weapons deal 6 / 3 / 2
  for effective / neutral / ineffective (`src/player.odin:37`). A Resistant
  bacterium with the wrong weakness could become effectively unkillable.
- **Base stats are not final**, so buff magnitudes must not be tuned yet. They are
  to be stored as absolute values in a separate `BUFF_DEFS` table, deliberately
  **not** derived from `BACTERIA_DEFS` — otherwise changing a bacterium's base
  health silently rescales every buff.
- Buffs need a visual tell, or the player cannot learn to prioritize. Species color
  already carries identity (`r/g/b` per species, with Staph, Ecoli, and
  Pseudomonas all 50x50 in distinct colors), so the buff visual needs its own
  channel rather than competing for color.

### Open questions (not yet decided)

- **Should Frenzied be additive-with-cap rather than freely multiplicative?**
  Blocks tuning.
- **Does Resistant stack multiplicatively with weapon weakness?** Could make a
  bacterium effectively immune.
- **What visual channel do buffs use?** One outline per category is the current
  leaning, held loosely. Does not need resolving before the skill tree.

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

- **The simulation is currently non-deterministic and violates this rule.** Three
  sites need fixing:
  - `src/level.odin:146` — `formation_complete_time = u64(sdl.GetTicks())` must
    become a tick count.
  - `src/level.odin:157` — `if u64(sdl.GetTicks()) >= wave.formation_complete_time`
    is **always true**, since ticks only increase. The dive gate has never
    actually gated anything, and `formation_complete_time` is currently dead.
  - `src/game.odin:431` — `delta_time` derived from `GetTicks()` must be split:
    real elapsed time for motion, fixed increments for the tick counter.
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
remaining and has been removed, so the seed is the only source of a threshold. See
`ROADMAP.org` under "Threshold design".

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
with a distinguishing number.

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
  recomputed without simulating anything.
- `.Level` no longer means "level number" below the root derivation; it is reused
  for per-level draws with small numbers. A second category would restore strict
  meaning but is not worth it at this call count.
- Same seed in, same run out.
- `master_seed` lives on `World`, not `Game`. The transition path and
  `Level_Transition` both need to derive seeds and only see `World`. Selection —
  fixed from `--seed` or clock-derived — still happens once, in `game_init`, and
  must be written before `world_init` runs.

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
- `Level_Transition`, when implemented, will become the owner of level
  progression. `world_init` will then hold the only initial generation and the
  transition holds all later ones; the "one call site" rule applies per path, not
  per program.

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
- The boss meter and boss fights described in `ARCHITECTURE.md` are also deferred.
  Their interaction with fleeing-driven difficulty is an open question: two
  escalating systems can stack multiplicatively and quietly break difficulty
  tuning, so this should be decided before tuning begins.
