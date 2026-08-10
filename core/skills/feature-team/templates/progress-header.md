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

Everything below this block is the HUMAN-readable part — keep writing it the ship way,
in Vietnamese, since the user is the one reading it.
-->
