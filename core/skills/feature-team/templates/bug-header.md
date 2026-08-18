<!-- state
kind: bug
slug: {{slug}}
branch: -
worktree: -
step: check
phase: -
awaiting: check
round: 0
gate: none
verdict: -
note: {{--note của anh, nguyên văn | none}}
-->

# Bug: {{title}}

- Source: {{source}}
- Shop: {{shop}}
- Date: {{date}}

> **NOW:** under analysis, no verdict yet.

## Three legs — if one is missing, say so explicitly

### 1. The problem
- Symptom:
- Reproduces:
- Who hits it / how many shops:

### 2. The related code
- Flow goes through:
- `file:line`:

### 3. The shop's settings
- Actual configuration on the store:
- Read from (Firestore / admin / API):

## Cross-check
<!-- the settings say A while the code reads B → that is the break -->

## Verdict
<!-- exactly ONE of four; also write it into `verdict` in the state block above:
     fix          — cause clear, worth fixing (attach the fix + blast radius)
     skip         — cause clear, not worth fixing (state the blunt reason)
     need-data    — not certain, name SPECIFICALLY what the user should check
     need-logging — not certain, name the file:line to instrument, the fields, the condition
-->

<!--
The `state` block at the top is the MACHINE-readable part (ship-board.sh).

  kind      bug — differs from a feature in that the output is a DIAGNOSIS, not code
  step      check → waiting-user → fixing (only once the user says fix)
  awaiting  check | user | none
  verdict   - | fix | skip | need-data | need-logging

Once the user says fix and the bug spans several surfaces → `/feature-open <slug>`, and only then
does it get a branch, a worktree and the feature-team roles. A one-line bug needs none of that.

Everything below the state block is written in Vietnamese — the user reads it.
-->
