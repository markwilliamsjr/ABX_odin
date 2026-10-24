# Current Session

## Date

2026-10-24 (planning; prior implementation 2026-10-21 to 2026-10-22)

## Goal

Plan the Level and Wave Lifecycle slice before implementing it: settle how enemy
counts are represented, and how much generation variance early levels should have.

## What was worked on

Planning only. No source changes. Read `src/level.odin`, `src/procedural.odin`,
`src/game.odin`, `src/debug.odin`, and the slice documentation, then resolved the
design questions blocking "initialize all drawn waves".

## What was decided

**Enemy counts.** `3 + level*2` is a level budget, not a per-wave count. It is
split deterministically across `wave_count` waves: base share plus the remainder
to the earliest waves, floor 3, floor wins (a level may exceed its budget). Per-wave
counts stay roughly 3–6 across the run; level length carries the growth.

**Naming.** `WaveParams.total_enemies` → `enemy_budget`; `Wave.total_enemies` →
`enemy_count`; `wave_init` takes `enemy_count` explicitly, matching the
`level_number` precedent.

**Early-level determinism.** Variance ramps with level:

- Block 0 wave count draws `[1, min(level, 4)]` — level 1 is always one wave.
- Count jitter is 0 in block 0, ±1 from block 1.
- Levels 1–2 pin entry to top-center via a one-element `available_points` slice.
- Degenerate draws still consume their seed triples, following the `MAX_WAVES`
  precedent.

**Pool ceiling.** The final per-wave count is clamped to `MAX_ENEMIES`. Under the
split the clamp is defensive, but the base curve already exceeds 50 at level 24, so
it stays installed as the last guard.

## Problems discovered

- `total_enemies` had silently changed meaning: the original design treated it as
  a level budget, but `wave_init` consumes it as one wave's count.
- Under the per-wave reading, a level-10 level fields 69–138 bacteria against a
  budget of 23.
- `3 + level*2` exceeds `MAX_ENEMIES` at level 24 — an out-of-bounds into
  `wave.enemy_indices` and the bacteria pool.
- `DECISIONS.md` still described `Level.wave_count` as a "global total", which the
  per-level draw had already superseded.
- `ROADMAP.org`'s threshold table is written against per-wave counts and needs
  re-derivation once the split lands.

## Current task

Planning is complete; implementation has not started.

## Next step

Unit A of the agreed sequence — the behaviour-preserving rename:

1. `WaveParams.total_enemies` → `enemy_budget`
2. `Wave.total_enemies` → `enemy_count`
3. `wave_init` takes `enemy_count` explicitly, with the call site passing the
   budget unchanged
4. Build, then confirm `--level 10` behaves as before

Then B (loop every drawn wave), C (budget split + floor + jitter ramp + wave-count
ramp), D (entry pin for levels 1–2).

## Previously completed (2026-10-21 to 2026-10-22)

State and Input: `world.state` gating for update and render, menu → playing, Esc
pause, `--debug` direct start, and CLI flags (`--seed`, `--level`, `--no-vsync`,
`--help`). See `ROADMAP.org` for the completed checklist.
