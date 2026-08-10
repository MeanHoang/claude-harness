---
name: bug-check
description: Diagnose a bug and then STOP and report — never fix it. Three mandatory legs (the problem, the related code, the shop's settings), cross-checked, ending in exactly one of four verdicts: worth fixing / not worth fixing / needs the user to check something / needs logging. Use when the user says "/bug-check", "check bug này", "phân tích lỗi này", "bug này do đâu", "xem lỗi này thế nào", or hands over a defect report before deciding whether to fix it.
---

# Bug check — diagnose, then stop

**The output is a DIAGNOSIS, not code.** This is where it differs from `ship`: ship starts
from a task already committed to, whereas here the first question is *"is this worth fixing at
all?"* — and for many bugs the correct answer is no.

No branch, no worktree, no plan. One session, read three things, report, stop.

## Three legs — if one is missing, say so explicitly

| Leg | What to find | What not to do |
|---|---|---|
| **1. The problem** | Exact symptom, whether it reproduces, how many shops are affected | Do not take the reporter's description as fact — they describe *what they saw*, not *what is happening* |
| **2. The related code** | Where the flow goes, specific `file:line` | Do not infer from function names. Open the file |
| **3. The shop's settings** | The **actual** configuration on that store (Firestore / admin / REST API) | Do not assume the shop uses defaults — most bugs live exactly here |

Concluding with a leg missing makes the conclusion untrustworthy. Reporting *"could not see the
settings, no permission"* beats guessing.

## Cross-check — where the bug usually surfaces

Put the three legs side by side and look for the **mismatch**:

> **The settings say A while the code reads B — that is the break.**

Common shapes: a shop enables an option but the code reads a different field; a field exists on
the document but is not in the `pickFields.js` whitelist so the frontend receives `undefined`;
the settings are right but the surface being looked at is dead (legacy scripttag).

## Exactly ONE of four verdicts

| Verdict | When | Must include |
|---|---|---|
| `fix` | Cause is clear, worth fixing | How to fix + blast radius + whether other shops are affected |
| `skip` | Cause is clear, not worth fixing | The blunt reason: rare, the customer can work around it, the fix costs more than it saves |
| `need-data` | Not certain, missing data | **Specifically** what the user should check — "see whether shop X has Y enabled", not "need more information" |
| `need-logging` | Not certain, needs observation | Which `file:line` to instrument, which fields to log, what condition to wait for |

Write the verdict into the `state` block of `progress.md` so it surfaces on `/ship-board`.

**Stop there.** Do not fix it even when the fix is obviously one line — that call belongs to the user.

## Fitting into the multi-parallel system

**State**: create `.claude/ship/<slug>/progress.md` from
`.claude/skills/feature-team/templates/bug-header.md`. It carries `kind: bug`, so `/ship-board`
lists it alongside features, with the **VERDICT** column showing what it is waiting on.

**Hard bugs can fan out** — the three legs are independent, so they parallelise the same way scout
does:

| Session | Does |
|---|---|
| A | Reproduce and collect symptoms, read logs |
| B | Read the code, map the flow |
| C | Read the shop's actual settings |

Then one pass to cross-check. **Only fan out when the bug is genuinely hard** — three sessions for
a small bug costs more than doing it straight.

**Upgrade path**: the user says `fix` →
- One spot, one file → fix it in the main checkout, get an OK, commit
- Multiple surfaces or needs phasing → `/feature-open <slug>`, then change `kind: bug` to
  `feature` in `progress.md`. Nothing is redone from scratch.

## Hard rules

- **Every claim about code behaviour carries `file:line`**, or says plainly "not verified —
  assumption".
- **Never write to a production store.** Read only. Writing requires asking the user first.
- Not sure of the cause → say you are not sure. `need-data` and `need-logging` are legitimate
  verdicts, not failures.
- If the bug came from someone else's commit on master → report the commit + author, do not fix it
  yourself (`ship` calls this ATTRIBUTION).
