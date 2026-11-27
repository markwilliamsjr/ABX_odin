# Roadmap 3B — Scrolling layered background

Status: active
Roadmap: ROADMAP.org 3B
Decisions: DECISIONS.md "Background composition", "Determinism", "Seeding"
Session: SESSION.md
Docs updated: 2026-11-26

Steps only, no code.

## Scope

Add two vertically scrolling layers of seeded 32×32 animated panels behind the
play field and menu. It does not add camera motion, gameplay-driven parallax, or
branding assets; palette, typography, and logo remain Phase 12. Player-visible
behavior changes: the arena gains a moving backdrop.

## Decisions already settled

- Two layers; the back scrolls slowly and the front quickly. (DECISIONS
  "Background composition")
- Sixteen panels: eight back-layer and eight front-layer; each level draws a
  cohesive seeded subset. (same)
- Each panel loops through 3–4 frames. (same)
- The front layer is sparse, roughly 30–40% occupancy. (same)
- The tile pattern is periodic in Y; 128 rows is the starting period. (same)
- Scroll and animation advance in `.Menu` and `.Playing`; they freeze in
  `.Paused` and `.Level_Transition`. (same)
- Presentation only; no gameplay decision reads it. (DECISIONS "Determinism")
- Generated selection uses `derive_seed`; append `.Background` to
  `SeedCategory`. (DECISIONS "Seeding", "Background composition")

## Before you start

- Confirm `odin check src` is clean.
- Confirm Phase 3's frame limiter has landed, since the scroll speeds are tuned
  against the final pacer.
- Capture a baseline frame-time reading with `--debug`.
- Decide the atlas file layout and write it down before drawing panels, so the
  source-rect arithmetic has one description.

## Steps

### 1. Atlas and panel metadata — assets, `src/background.odin`

- Add a 16-column × 4-frame atlas of 32×32 panels. Reserve panels 0–7 for the
  back layer and 8–15 for the front.
- Add panel metadata for frame count and source rectangles.
- Load the atlas through `image_texture_load`, store it on `Assets`, and destroy
  it in `assets_destroy`.
- Check: the atlas loads under the dummy driver; every panel/frame source rect
  is in bounds; no texture leak at shutdown.

### 2. Seeded per-level composition — `src/background.odin`, `src/level.odin`

- Add a `Background` value and initialize it from the level seed after that seed
  is derived in `level_init`.
- Append `.Background` to `SeedCategory` and derive the per-level subset and the
  per-tile panel/orientation from it.
- Build a periodic `[period_rows][columns]` tile pattern per layer. Keep the
  period a named constant.
- Check: same seed produces the same subset and pattern; different seeds differ;
  every selected panel belongs to the level subset.

### 3. Scroll, wrap, and animate — `src/background.odin`, world update

- Store `scroll_y` per layer and advance it from `delta_time` in `.Menu` and
  `.Playing` only.
- Render rows through the modulo pattern row plus the scroll offset; draw one
  extra row above and below the screen.
- Step the animation frame from a real-time clock:
  `frame = (anim_frame + panel_offset) % panel.frame_count`.
- Check: scrolling wraps without a visible jump; pause and transition hold the
  offset and frame; frames advance while playing and in the menu.

### 4. Render integration — `render_world`, `render_menu`

- Draw the back layer, then the front layer, immediately after the clear and
  before the player, bullets, and bacteria.
- Reuse the same background in the menu.
- Make blend mode and alpha behavior explicit for the sparse front layer.
- Check: entities render over the background; the menu shows the same backdrop;
  the transition overlay dims a held frame.

### 5. Verification and cleanup — whole slice

- Run the same-seed replay and the frame-time check.
- Remove temporary instrumentation and compare source hashes if temporary edits
  were used.
- Update `PROJECT.md`, `SESSION.md`, and the roadmap checkboxes.
- Check: every 3B box is ticked or consciously deferred; `odin check src -vet`
  is clean.

## Open choices

None architectural. The remaining values are tuning and are listed below.

## Deliberately not doing

- No camera motion or player-movement parallax; the layers scroll autonomously.
- No gameplay or collision changes.
- No final palette; 3B uses a temporary palette and Phase 12 recolors the atlas.
- No foreground layer over the play field.
- No pre-baked layer texture; measure the straightforward per-tile draw first.

## Verification

- `odin check src` and `odin check src -vet`.
- Same seed twice: identical subset, panel, and orientation per tile.
- Different seeds: observably different subsets and layouts.
- All 16 panels appear across a few levels.
- No visible wrap seam at the period boundary.
- The front layer visibly reveals the back layer.
- Pause and level transition hold the scroll offset and animation frame.
- Frame time remains acceptable with the debug overlay.
- Gameplay, collision, and wave logs are unchanged.

## Gate

Phase 3B is done when both layers render, scroll, wrap, and animate from the
level seed; the menu and playing states advance the clock; pause and transition
freeze it; and the verification list passes. Tick 3B.1–3B.5 and update
`PROJECT.md` and `SESSION.md`.

## Tuning left open

- Back/front scroll speeds (starting 20/60 px/s).
- Per-level subset split (starting 4 back + 4 front).
- Front occupancy (starting 30–40%).
- Pattern period (starting 128 rows).
- Animation frame rate (starting 8 fps).
- Whether any of the above vary by level block.

## Outcome

Added when the step closes.
