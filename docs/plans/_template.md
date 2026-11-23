# Roadmap N.N — <title>

Status: active        <!-- active | done | abandoned -->
Roadmap: ROADMAP.org N.N
Decisions: DECISIONS.md "<section>"
Session: SESSION.md
Docs updated: YYYY-MM-DD

Steps only, no code.

## Scope

One sentence for what this step does. One sentence for what it deliberately does
not do. State whether player-visible behavior changes.

## Decisions already settled

Only the constraints this step depends on, with pointers to where they are
recorded. Do not reopen settled decisions here.

## Before you start

- Compile or type check.
- Capture any baseline log or state needed to verify the step later.
- Note temporary edits you expect to make and revert.

## Steps

Group by file, then by concern. For each step:

- Name the function or branch it plugs into, using symbols rather than line
  numbers.
- Say what is added or changed, and why it belongs in this step.
- Record the per-step check.

## Open choices

Only choices that are still genuinely open.

For each one: the options, the tradeoff in one line each, and a recommendation
marked as a recommendation.

If nothing is open, say so explicitly.

## Deliberately not doing

- The tempting adjacent work that is excluded.
- The later step or phase that owns it.
- Any seam left for that work, and what must not change when it lands.

## Verification

- Compile or type check.
- Behavioral check for the new code.
- Regression check for existing behavior.
- Same-seed replay where generation is involved.
- Any temporary edit needed to exercise an otherwise unreachable path.

## Gate

What must be true before the next step starts. Which roadmap boxes tick, and
which project notes need updating.

## Tuning left open

Values or parameters that are deliberately provisional, and who owns them.

## Outcome

Added when the step closes. What landed differently from the plan, and why.
Anything still outstanding.
