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
- `Level.wave_count` is the global total, used for debug display and seed
  derivation. A separate `wave_index` tracks position within the current level.
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

## Fleeing and returning

### Decision

Bacteria flee when the number remaining in a wave drops below a percent
threshold. That threshold is a seeded random draw, rolled **once per wave** at
spawn time and compared deterministically on every subsequent frame.

Fled bacteria are not removed. They withdraw and return in a later wave,
strengthened.

### Reason

Two separate reasons, both important.

First, a single roll preserves determinism. A per-frame probabilistic roll would
make runs irreproducible, contradicting the determinism principle in
`PROJECT.md`. Rolling once at spawn and comparing thereafter keeps replay intact.

Second, fleeing-and-returning is the difficulty-escalation mechanism that
`ARCHITECTURE.md` describes as *"the next wave bacteria is determined by what the
player is not killing."* Bacteria that fled are by definition bacteria the player
did not kill. The document describes the effect; this specifies the cause.

### Consequences

- Fleeing is not a fail-state escape valve. It is the primary difficulty
  escalation engine.
- Wave resolution has **three** cases, not two: dead (resolved), fled (resolved
  *and* scheduled to return), still alive (unresolved).
- Fleeing is evaluated per wave, not per level.
- A fled bacterium requires a pending roster that outlives the wave, so that
  roster lives on `Level` or `World`, not on `Wave`.
- Return scheduling must use seeded RNG, or determinism breaks.
- This is a *partial* realization of the architecture doc's adaptive bias. True
  wave-composition bias — skewing spawns toward species the player is not killing
  — remains separate, deferred work that depends on a kill-count system that does
  not exist.
- Wall-clock time (`sdl.GetTicks()`) must not appear in any generation or
  threshold decision.

### Open questions (not yet decided)

- **Strengthening model.** Health scaling, stat scaling, or tier promotion.
  Tier promotion would connect to `species_unlocked`, which is computed at
  `src/procedural.odin:124` and never read.
- **Return scope.** Same level only, or do pending bacteria carry into the next
  level?
- **Identity on return.** Does a returning bacterium keep its identity, enabling
  future kill-count tracking, or is it a fresh entity? This affects the
  wave-completion predicate.

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

### Reason

Self-documenting, and avoids overloading an existing category with a second
meaning.

### Consequences

- `derive_seed` numbers must be **globally monotonic across an entire run**, not
  per-level. `level_init` currently passes a hardcoded `0`; without a global wave
  number, wave 1 of level 5 and wave 1 of level 9 receive identical seeds.
- Every `derive_seed` call must use a `(category, number)` pair that is unique
  across a full run. Same seed in, same run out.

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
- Every `GameState` variant should be reachable so none remains a dead enum value.

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
