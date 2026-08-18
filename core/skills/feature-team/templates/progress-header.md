<!-- state
kind: feature
slug: {{slug}}
branch: {{branch}}
worktree: {{worktree_path}}
step: 1
phase: -
awaiting: scout
round: 0
gate: none
verdict: -
-->

# Ship: {{title}}

- Task: {{notion_url}}
- Branch: `{{branch}}`
- Worktree: `{{worktree_path}}`
- Plan doc: `.claude/ship/{{slug}}/plan.html`

> **NOW:** just created, scout is running Gate 1.

## Phases
| # | Phase | Surface | Status |
|---|---|---|---|
| P1 | | | ⬜ |

<!--
The `state` block at the top is the MACHINE-readable part (ship-board.sh). Update it after EVERY turn.

  kind      feature | bug
  step      0..7 per ship
  phase     P1/P2/... or "-"
  awaiting  who must act next: scout | coder | research | reviewer | ux | checker | user | none
  round     coder↔reviewer rounds on the current phase (3 means escalate to the user)
  gate      none | plan | code | decision   ← anything but "none" means WAITING ON THE USER
  verdict   - | fix | skip | need-data | need-logging   (bugs only)

Three more fields are written by hooks, not by you — do not hand-edit them:

  session   id for `claude --resume` after the machine restarts (ship-state-sync.sh)
  head      commit at the end of the last turn
  updated   when that turn ended

Everything below this block is the HUMAN-readable part — keep writing it the ship way,
in Vietnamese, since the user is the one reading it.

WHAT BELONGS IN THIS FILE, AND WHAT DOES NOT:

  progress.md   the WORK ITEMS. What is left, what is blocked, what is waiting on the user —
                the thing you and the user read to know what to do next. Keep it short enough
                to read on one screen (~150 lines). It gets read at the start of every session,
                so a bloated one costs context on every single turn.
  decisions.md  the REASONS. What was chosen and why, what was rejected, technical debt,
                lessons. Append-only, grows without limit, read when you need the why.

Do not turn progress.md into a log. Work that is finished collapses into one ✅ line here and
moves its reasoning to decisions.md. A 900-line progress.md is a bug: it makes the file useless
for its one job — telling someone what to do next.
-->
