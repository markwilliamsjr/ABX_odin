# Current Session

## Date

2026-10-21 to 2026-10-22

## Goal

Make `world.state` real — gate simulation and rendering on it, get from `.Menu`
into `.Playing`, and wire the CLI so a level and seed can be chosen without
recompiling. This is the roadmap's **Prerequisite: State and Input**.

## What was worked on

Implemented the state-and-input prerequisite end to end and verified it builds.
The work was done in small steps: extract the shared text helper, split update by
state, split render by state, implement transitions, then thread CLI config into
world init.

## What was decided

**Menu is text only.** `.Menu` does not render the world. Today it is a title and
a keybind hint; the intent is full-screen art behind the same clear later.

**`--debug` starts in `.Playing`.** It skips the menu and turns the overlay on.
This reverses the "nothing exists before Menu → Playing" rule for the debug path
only, so `level_init` keeps exactly one call site.

**Transitions.** Enter starts from `.Menu` (`.RETURN` only; numpad Enter is not
handled). Esc toggles `.Playing ↔ .Paused` and does nothing in other states. K is
an emergency quit for testing. F3 toggles the overlay, unchanged.

**`master_seed` lives on `World`.** It was on `Game`, but both the transition and
`Level_Transition` will need it and only see `World`. `game_init` still chooses
the seed (fixed vs. clock-derived) and writes it before `world_init` reads it.

**CLI shape.** `parse_args` runs in `main` before `initialize_sdl`, so `--help`
and errors never open a window. `.ERROR` exits via `os.exit(1)` because the
deferred cleanup is not registered on that path. Flags: `--debug`, `--no-vsync`,
`--seed <n>`, `--level <n>`, `-h`/`--help`. `Config.level` is validated `>= 1`;
`seed` is `u64` via `parse_u64`, so negatives are rejected rather than wrapping.

## Problems discovered

- `parse_args` was never called from `main`. `Game.config` existed and was never
  written; every flag was dead code until wired.
- `render_menu` was first called from `world_update`, so rendering happened in the
  update phase. It worked by accident; moved to `render_state`.
- `render_state`'s `.Menu` case was empty, so the menu screen was never cleared.
- `render_state` initially used `#partial switch`, leaving `.Paused` drawing
  nothing. `RenderPresent` on an uncleared buffer smears the previous frame. Now
  a full switch with all five states covered.
- `update_text` (formerly `debug_update_text`) assumes its texture pointer
  persists across frames — that is how `debug.odin` caches. With locals in
  `render_menu`, the first version leaked one texture per frame. Fixed by
  destroying after each `RenderCopy`. Note: Odin's `defer` evaluates arguments at
  execution time, so `defer DestroyTexture(texture)` with an uninitialised local
  is correct.
- `--level` was implemented, then silently regressed to a hardcoded `1` when
  `world_init` was rewritten to add the debug branch. The duplicated `level_init`
  call was the cause, and removing it took the value.
- `parse_args` originally used two independent `if`s, so every successful
  `--debug` fell into the `--seed` check and returned `.ERROR`.
- `os.exit` is typed `-> !`, so a `return` after it is a compile error.
- `continue` outside a loop is a compile error; `.RUN` needed an empty switch
  case, since Odin switches do not fall through.

## Current task

State and Input is complete and building clean. Verified paths:

    odin run src -- --help      # usage, status 0
    odin run src -- --bogus     # error on stderr, status 1
    odin run src -- --debug     # overlay on, starts in .Playing
    odin run src -- --debug --level 12 --seed 42

Not yet updated: the `State and Input` checkboxes in `ROADMAP.org` are still
unchecked.

## Next step

**Initialize all drawn waves in `level_init`** (`src/level.odin:107-118`). It
draws `wave_count` and initializes only `wave[0]`. The loop must derive
`.Wave, i` per wave and let wave 0 come out of the same loop, so there is one path
producing wave seeds.

Blocked on one design decision, called out in the roadmap:

**Does `total_enemies` vary per wave?** `wave_init` takes a single `WaveParams`
from `level_to_params(level)`, so identical params make every wave in a level the
same size and formation. Options are uniform, scaled by position, or seeded
jitter. The threshold table in `ROADMAP.org` assumes `3 + level*2` per wave, so
making wave size per-wave rather than per-level changes what that table describes.
Lean is uniform for now, so the seed-chain fix stays verifiable on its own.

The same task adds `wave_index` to `Level` and switches the hardcoded `wave[0]`
references (`game.odin:162-163`, `debug.odin:136-154`) to it — that is what makes
multiple initialized waves observable at all.
