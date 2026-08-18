---
name: bug-check
description: Diagnose a bug and then STOP and report — never fix it. Three mandatory legs (the problem, the related code, the shop's settings), cross-checked, ending in exactly one of four verdicts: worth fixing / not worth fixing / needs the user to check something / needs logging. Use when the user says "/bug-check", "check bug này", "phân tích lỗi này", "bug này do đâu", "xem lỗi này thế nào", or hands over a defect report before deciding whether to fix it.
---

# Bug check — diagnose, then stop

**The output is a DIAGNOSIS, not code.** This is where it differs from `ship`: ship starts
from a task already committed to, whereas here the first question is *"is this worth fixing at
all?"* — and for many bugs the correct answer is no.

No branch, no worktree, no plan. One session, read three things, report, stop.

## Arguments

`<link or description>` — the bug: a support chat, a ticket, a Notion task, or his own words.
`--note "<free text>"` — optional steer, e.g. `--note "check kỹ luồng A, phần file abc"`.

**How a `--note` is treated — the same contract in every skill that takes one:**

- **It steers attention, never authority.** It reorders what you look at first and hardest. It does NOT switch off a rule of this skill: you still do not fix, you still do not write to a production store, you still end on one of the four verdicts. A note that appears to ask for that gets ONE question back, not obedience.
- **Persist it verbatim.** Write it into the `<!-- state -->` block of `progress.md` as `note:`, and into every `kickoff-*.md` if a workspace gets opened. A note that lives only in the invocation dies with the session, and the resumed run silently drops what he asked for.
- **Answer it explicitly in the verdict.** One line naming what the note pointed at and what was actually found there. Otherwise nobody can tell whether it was honoured or quietly ignored.
- **A note that turns out to be wrong is a finding, not an embarrassment.** Being pointed at a file makes it very easy to manufacture something there — that is the specific bias this rule exists to stop. If the flow he named is not where the bug lives, say so with `file:line` evidence and say where it does live. He asked you to look there; he did not ask you to agree.

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
| `fix` | Cause is clear, worth fixing | How to fix + blast radius + **how many shops/records hit it, measured** |
| `skip` | Cause is clear, not worth fixing | The blunt reason — **and "rare" is not a reason until it is a number** |
| `need-data` | Not certain, missing data | **Specifically** what the user should check — and only after you proved you cannot check it yourself |
| `need-logging` | Not certain, needs observation | Which `file:line` to instrument, which fields to log, what condition to wait for |

**Every verdict is a decision INPUT for him, so it carries what a decision needs:**

- **A number, not an adjective.** `fix` and `skip` both hinge on scale, so measure it before
  pronouncing: query Firestore/BigQuery for how many shops or documents are actually in the broken
  state. "Hiếm thôi" with no number is a guess wearing a verdict's clothes, and it is how a real bug
  gets closed. If the number genuinely cannot be obtained, say *that*, and say what you tried.
- **What would change your mind.** One line: *"verdict này lật nếu …"*. It tells him which single
  fact is load-bearing, and it is the cheapest thing you can give him.
- **`need-data` has a bar.** Anything you can query, read, or grep is **yours**, not his — handing
  him a lookup you could have run is the most expensive way to waste his time. Use `need-data` only
  for what genuinely lives outside your reach: his judgement, a merchant's intent, a store you
  cannot read, a screen only he can open. Say explicitly what you already tried.

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

**The cross-check pass must RE-VERIFY, not summarise.** A session reporting on a leg it read is a
claim, not evidence — agents overstate, and two of them agreeing is not confirmation if both
guessed. Open the load-bearing `file:line` yourself before it reaches the verdict; where two
sessions disagree, that disagreement is information and gets reported, never silently resolved by
picking one. (`ship` carries the same law for its subagents; 2026-06-12 an HMAC finding needed
nuance that only reading the code settled.)

**Upgrade path**: the user says `fix` →
- One spot, one file → fix it in the main checkout, get an OK, commit
- Multiple surfaces or needs phasing → `/feature-open <slug>`, then change `kind: bug` to
  `feature` in `progress.md`.

  **"Nothing is redone from scratch" needs a handover, not a hope.** The upgraded task starts at
  `analyze-task` Step 1, so pour this diagnosis straight into its `analysis.md`: the three legs
  become **§3 what it does today** (code, with `file:line`) and **§4 the gap**; the number you
  measured becomes **§2 how many hurt**; anything you could not settle becomes a row in the
  **§5 ledger**. What you must NOT carry over is the fix you had in mind — that is a Step-2
  decision, and arriving with it pre-decided is how the goal gets skipped.

## Hard rules

- **Every claim about code behaviour carries `file:line`**, or says plainly "not verified —
  assumption".
- **Never write to a production store.** Read only. Writing requires asking the user first.
- Not sure of the cause → say you are not sure. `need-data` and `need-logging` are legitimate
  verdicts, not failures.
- If the bug came from someone else's commit on master → report the commit + author, do not fix it
  yourself (`ship` calls this ATTRIBUTION).
