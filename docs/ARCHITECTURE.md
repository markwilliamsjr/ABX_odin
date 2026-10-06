# Game Architecture

This document describes the **intended** design, not the current
implementation. What exists today is tracked in `PROJECT.md` and `ROADMAP.org`.

Rationale for settled decisions lives in `DECISIONS.md`.

## Gameplay

Bacteria spawn in procedurally generated formations. After each level the player
levels up and is presented with a Path of Exile like skill tree to upgrade their
antibiotic.

As the player moves through levels, different types of bacteria become able to
spawn.

A **level** is a sequence of waves. Some levels contain a single wave; others
contain more. The number is drawn from the run seed, with the range growing as
levels increase.

A **wave** determines:

- number of enemies
- formation
- formation bounds
- enemy types
- spawn information

Formation generation happens before spawning.

## Ending a wave

A wave ends when every bacterium spawned in it is resolved. Resolution has
exactly three cases:

| Case | Result |
|---|---|
| Destroyed | Resolved |
| Fled | Resolved, and queued to return |
| Still alive | Unresolved; the wave continues |

There is no other exit. In particular a wave does not end on a timer.

## Fleeing, resistance, and returning

Fleeing is not an escape valve. It is the primary difficulty-escalation engine:
*"the next wave's bacteria is determined by what the player is not killing."*
Bacteria that fled are by definition bacteria the player did not kill.

### Trigger

Each wave draws a flee threshold from the seed **once**, at spawn. On every
subsequent frame the threshold is compared deterministically — no per-frame
probability anywhere in the flee path. When the number of remaining bacteria
crosses the threshold, they flee and the wave resolves at that moment.

### Resistance

A fleeing bacterium is not destroyed and does not change species. It withdraws,
then returns having developed **resistance**. Four categories:

- **Hardy** — increased maximum health
- **Resistant** — reduced damage taken
- **Biofilm** — absorbs the first N hits
- **Frenzied** — increased speed

Each escape grants one category and restores the bacterium to spawn max health.
Because escapes compound, a bacterium can be fled on repeatedly and stack
resistance, up to five slots.

### The return queue

Fled bacteria queue to return, and the queue **survives level transitions**. A
bacterium enters the *next wave* after its escape; if it escapes again, it enters
the wave after that. A level therefore never opens with the whole backlog at once
— it arrives one wave at a time.

The queue lives on the world, not on a level or a wave.

### Bosses

There is a hidden boss fight meter that fills as the player completes levels,
raising the likelihood of a boss fight; it resets after one.

At a boss level, **every bacterium must be destroyed** before the player can
advance. Fleeing is not permitted there.

This makes bosses the pressure valve for the resistance system. Without a
periodic hard-clear, a bacterium could be escaped on indefinitely; with it,
escapes are bounded across a run and the roster develops a rhythm — build up,
flush, rebuild — rather than a monotonic ramp.

## Seeding

Every generated value is derived from the run seed through `derive_seed`, which
hashes a `(category, number)` pair against a parent seed. The derivation graph is a
**chain of trees** rooted at the run seed:

```
root
└─ derive_seed(root, .Level, level_number)     → level_seed
   ├─ derive_seed(level_seed, .Level, 0)       → the level's wave count
   ├─ derive_seed(level_seed, .Wave, i)        → wave_seed, i = 0..wave_count-1
   │  └─ derive_seed(wave_seed, .Entry, 0)    → entry path rng
   └─ derive_seed(wave_seed, .Level, 0)        → that wave's flee threshold
```

`level_seed` carries per-level decisions; `wave_seed` carries per-wave decisions.
A wave's index within its level is its seed key, so a wave seed is a pure function
of `(run seed, level, wave index)` and needs no run history to recompute.

The invariant is that no `(parent_seed, category, number)` triple is ever reached
twice in a run. The same `(category, number)` under a *different* parent is fine —
this is what lets `.Level` name both a level and a decision made within it.

## Determinism

The same seed produces the same generated content. Determinism covers *decisions*,
not *motion*:

- A tick counter drives every decision and branch point.
- Real elapsed time moves things, and never decides anything.
- No decision may read wall-clock time.
- A decision may depend on continuous motion only when that motion is itself
  tick-driven.

What this buys is reproducibility of the run's *structure* — wave counts,
formations, flee thresholds, buff rolls — which is what makes a bug report
reproducible. Identical gameplay outcomes are not asserted, and could not be with
a human at the controls.

## Formation generation

Formations, the mix of bacteria types, total bacteria spawned, and the layout are
all procedurally generated from a set of rules.