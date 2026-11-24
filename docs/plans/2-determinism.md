# Roadmap 2 — Determinism

Status: active — steps 1–3 landed (`odin check src` clean); step 4 next
Roadmap: ROADMAP.org 2
Decisions: DECISIONS.md "Determinism", "State machine", "Vet review cadence"
Session: SESSION.md
Docs updated: 2026-11-24

Steps only, no code.

## Scope

Make every decision and branch point read a tick counter, leaving real elapsed
time for motion only. It does not retune timing values or change gameplay feel:
the 0.3s spawn interval and dive timing should land on the same real-time
cadence at 60 fps. Player-visible behavior should not change, apart from the
removal of a dive gate that currently never gates anything.

## Decisions already settled

- Determinism means deterministic decisions with continuous motion: a tick
  counter for decisions, real elapsed time for motion, and no wall-clock read in
  a decision. (DECISIONS "Determinism")
- Every decision and branch point reads the tick counter. A fixed timestep for
  the whole loop was rejected because it changes game feel; a seeded fixed delay
  for formation completion was rejected because it decouples the fiction from
  what is on screen. (DECISIONS "Determinism")
- `formation_complete` is the one real threat to the rule: today it is derived
  from continuous entry motion, so it can land on different ticks across runs.
  It must become tick-driven, and a decision may depend on continuous motion
  only when that motion is itself tick-driven. (DECISIONS "Determinism")
- A tick is a **fixed-rate accumulator** (60 ticks per second), not one tick per
  frame. Timing must stay stable once Phases 3 and 5 make the FPS cap
  configurable. This slightly reinterprets "increments by a fixed amount each
  update"; the reinterpretation is recorded in "Determinism".
- Entry motion is driven by the tick-derived step, so `.Holding` is reached on a
  deterministic tick while remaining coupled to visible motion.
- The always-true dive gate is removed. `wave_dive_update` already stops while
  formation is incomplete; a deliberate post-formation pause belongs to Phase
  3A if wanted.
- Behavior timers (dive, burst, cooldown) and the animation frame timer are
  classified as motion/presentation and deferred to Phase 6. Wall-clock
  timestamps used only in logs are not decisions. (DECISIONS "Determinism",
  "Flee animation phase")
- The level transition uses an accumulator rather than `sdl.GetTicks`, and its
  expiry is a branch point, so it reads the tick clock. (DECISIONS "State
  machine")
- Vet runs at the end of each top-level phase, not after each step. Phase 2 is
  not verified while `odin check src -vet` is dirty. (DECISIONS "Vet review
  cadence")

## Before you start

- Confirm `odin check src` is clean. Note that roadmap 1.7 (unit tests) and 1.8
  (vet review) are still unchecked, so starting Phase 2 is a deliberate phase
  ordering deviation; accept that a future 1.7 test seam may need to drive
  values whose shape this phase changes.
- Capture the 1.6 same-seed baseline log for generated fields. Generation
  happens at init and must remain byte-identical.
- The stale line references in DECISIONS "Determinism" (`level.odin:196`, `:206`,
  `game.odin:548`) were corrected when steps 1–3 landed; that bullet now
  describes the two remaining sites instead of three.
- Note the temporary edits to make and revert: `delta_time` jitter injection for
  the decisive determinism check, and logs of decision ticks. Compare source
  hashes afterwards, as in 1.6.

## Steps

### 1. Produce ticks at one wall-clock site — `src/game.odin`, main loop

- Keep `sdl.GetTicks` as the only wall-clock read in the program. Both calls in
  the loop are that one clock: the pre-loop `last_time` seed and the per-frame
  `current_time`. Do not pass either raw value into the simulation.
- From `delta_time`, accumulate a remainder and emit two tick values per frame:
  `ticks_this_frame` (elapsed this frame) and `total_tick` (monotonic running
  total). Clamp `ticks_this_frame` to `MAX_TICKS_PER_FRAME`; the overrun policy
  is in Open choices.
- Pass both values explicitly into `world_update` alongside `delta_time`.
  Explicit data flow is preferred over hidden state on `World` (PROJECT
  "Important Principles").
- Keep the accumulator and its remainder in one place so no other system can
  read wall-clock time.

Check: a stable 60 fps produces one tick per frame on average; a stall is handled
according to the chosen overrun policy without a burst of decisions; a temporary
log shows no other `GetTicks` call site feeding a decision.

### 2. Convert the transition accumulator — `src/game.odin`, `world_update`

- Plugs into the `.Level_Transition` branch, where `elapsed` is accumulated and
  compared against `duration`.
- Make both fields tick-domain so expiry reads the decision clock. This is
  control flow, so leaving it on real time would violate the rule.
- Phase 5/7 will own the hold duration; do not add settings or UI here.

Check: the hold still lasts the same real time at 60 fps, and exactly one
`transition start` / `transition end` pair fires per level.

### 3. Move wave timers into ticks — `src/level.odin`, `Wave` and `wave_init`

- Plugs into `Wave.spawn_timer`, `Wave.dive_timer`,
  `Wave.formation_complete_tick`, and `Wave.flee_start_tick`, all reset in
  `wave_init`.
- Split the fields by meaning. `spawn_timer` and `dive_timer` are accumulators:
  they add `ticks_this_frame` and stay integer counters.
  `formation_complete_tick` and `flee_start_tick` are timestamps: they store
  `total_tick`, and elapsed time is read as `total_tick - stamp`. The `_tick`
  suffix is deliberate: no field holding ticks may be named `_time`.
- Change them to tick-domain integers. Convert `spawn_delay` and `dive_delay`
  once at the initialization boundary so the current 0.3s interval is preserved
  at 60 fps rather than silently retuned.
- Keep `flee_start_tick` meaningful for the elapsed-time log, but in ticks.

Check: a stable 60 fps run spawns at the same real-time intervals as the
baseline; same seed still produces identical generated fields at wave init; a
timestamp taken before an accumulator clamp still reads a sane elapsed value.

### 4. Convert the two timer comparisons — `src/level.odin`, `wave_update` and
`wave_dive_update`

- Plugs into the spawn gate (`spawn_timer` versus `spawn_delay`) and the dive
  gate (`dive_timer` versus `dive_delay`).
- Make both integer tick comparisons. Add `ticks_this_frame` to the timer, then
  keep the existing one-spawn / one-diver-selection-per-frame behavior: compare
  `>=`, subtract the delay once.

Check: no spawn or selection consumes more than one slot per frame, even when
several ticks land in one frame.

### 5. Remove the vacuous dive gate — `src/level.odin`, `wave_dive_update`

- Plugs into the `GetTicks() >= formation_complete_tick` comparison, which is
  always true because the clock is monotonic and the timestamp is in the past.
- Delete the comparison. The `formation_complete` early return already gates
  diving, so this changes no behavior and removes a wall-clock read from a
  decision path.

Check: diving still starts only after formation completes and still selects at
most one diver at a time.

### 6. Make formation completion tick-driven — `src/level.odin` and
`src/enemy.odin`

- Plugs into the formation check in `wave_update`, which currently sets
  `formation_complete` when every owned bacterium is `.Holding`, and into the
  entry update path that reaches `.Holding`.
- Pass the tick-derived step (`ticks_this_frame / TICK_RATE`) into the entry
  update instead of raw `delta_time`, so the transition to `.Holding` happens on
  a deterministic tick. Real elapsed time continues to move everything else.
- The entry blocks are duplicated across the four species. Touch only the entry
  path needed here and accept the duplication until Phase 6 removes it.

Check: with jitter injected into `delta_time`, the tick on which
`formation_complete` becomes true is unchanged, and bacteria are visibly
holding when it fires.

### 7. Remove dead wall-clock writes — `src/enemy.odin`

- Plugs into the eight `cold.state_start_time = sdl.GetTicks()` assignments in
  the entry and return update blocks.
- They have no readers, so remove them. If Phase 6 later wants a state timer, it
  will reintroduce one in ticks.

Check: no `sdl.GetTicks` call remains outside the main loop; `odin check src`
is clean.

### 8. Update the docs — `docs/DECISIONS.md`, `docs/SESSION.md`

- Amend "Determinism" with the accumulator tick semantics and the deferred-timer
  classification. The line references and tick-domain field names were corrected
  when steps 1–3 landed; keep the Consequences bullet in sync if steps 4–7 move
  the remaining sites.
- Record the step outcome in `SESSION.md`: tick rate, clamp policy, and what was
  observed in the jitter check.

Check: the docs describe the implementation that landed, not the old code.

## Open choices

The four design choices — tick semantics, formation-completion mechanism, dive
gate, and audit scope — are settled. Two implementation details remain:

**1. Accumulator overrun on a long frame.**
- Clamp ticks to a maximum per frame and drop the excess: prevents a burst of
  decisions after a stall — recommended.
- Allow bounded catch-up over several frames: preserves elapsed time more
  exactly but can produce visible bursts.
Recommendation: clamp and drop the excess; record the potential drift.

**2. Flee log timestamps.**
- Use the tick clock for `flee_start_tick` and the elapsed-ms log: makes logs
  compare cleanly across same-seed runs — recommended.
- Leave the log on wall-clock time: it is not a decision, so the determinism
  rule permits it, but 1.6 already saw these lines differ between runs.
Recommendation: use ticks; logs are a verification channel and should be
byte-comparable.

## Deliberately not doing

- A fixed timestep for the whole main loop — rejected in DECISIONS, and it
  changes game feel. The seam left is the single tick producer in the loop; it
  must not grow into a full fixed-step simulation.
- Dive, burst, cooldown, and animation frame timers — Phase 6 owns the behavior
  blocks. Their classification as presentation is recorded above; when Phase 6
  refactors them, it must not reintroduce wall-clock reads into decisions.
- Frame pacing flags and the FPS limiter — Phase 3. Do not add `--vsync` or
  `--fps` here.
- Gameplay retuning — Phase 3A. The spawn interval is converted, not changed.
- The skill tree, Clay UI, bosses, and adaptive composition — Phases 4–9.

## Verification

- Compile: `odin check src` clean; `odin check src -vet` clean at the phase gate.
- Behavioral: spawn cadence still 0.3s-equivalent at a stable 60 fps; diving
  still requires formation completion; transition hold length unchanged.
- **Decisive check:** temporarily inject jitter into `delta_time` and assert the
  decision sequence — spawn ticks, formation-complete tick, first-dive tick,
  and transition tick — is unchanged. This proves decisions are actually
  tick-driven rather than merely using a tick variable.
- Confirm the dive gate is gone: log formation-complete tick and first-dive
  tick; `wave_dive_update` still stops while formation is incomplete.
- Regression: wave resolution, flee, roster FIFO/capacity, and level transition
  unchanged; 1.6's same-seed generated log remains byte-identical.
- Revert every temporary edit and confirm source hashes match the pre-test
  state.

## Gate

- Both Phase 2 boxes ticked in `ROADMAP.org`.
- DECISIONS "Determinism" records the fixed-rate tick semantics, the
  deferred-timer classification, and corrected line references.
- `SESSION.md` records the tick rate, clamp policy, and jitter-check result.
- `odin check src -vet` is clean; no new vet findings are deferred past this
  phase boundary.

## Tuning left open

- `TICK_RATE` (proposed 60) and `MAX_TICKS_PER_FRAME`. Owned by this phase's
  verification; raising the rate is the lever if entry motion looks steppy at
  high FPS.
- The tick-domain values of `spawn_delay` and `dive_delay`. Converted from the
  current seconds here; their feel is retuned in Phase 3A after frame pacing
  lands.

## Outcome

Added when the step closes.
