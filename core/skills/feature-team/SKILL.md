---
name: feature-team
description: Run ONE feature through the exact ship flow but with MANY specialised sessions (parent orchestrator + scout + coder + research + reviewer + ux + checker), coder ↔ reviewer bouncing findings until they converge, escalating to the user at only 3 gates — review plan, review code, settle a trade-off. Use when the user says "chạy feature team", "mở session cha", "chạy song song nhiều task", "để AI review AI rồi báo tôi kết quả cuối", or wants several features running at once.
---

# Feature Team — ship executed by specialised sessions

**This does not replace `ship`.** The steps for handling a feature stay exactly the same (Step 0→7). This skill only changes *who executes which step*: instead of one session playing every role, each role is its own session, and they iterate with each other until they converge before anything reaches the user.

**Why split roles rather than just run faster:** a session that just wrote code is biased toward its own code. The reviewer must sit in a **clean context** — it must never have seen that code being written. This is the writer/reviewer pattern; combined with the finding that 93.4% of bugs are caught by exactly one lens, the verifiers must have **different perspectives**, not be copies of each other.

## Layout

- **Isolation unit = feature** → one git worktree per feature.
- **Specialisation unit = session** → several sessions pointing at that same worktree (one tree, so what the coder writes the reviewer reads immediately — nothing to sync).

| Role | Does what | ship step |
|---|---|---|
| **Parent** | Creates the worktree, bootstraps it, opens child sessions, holds state, collects reports, decides when to escalate | throughout |
| **Scout** | Reads the Notion task, verifies every claim against code, multi-surface flow-check, writes `plan.html` | Step 0–2 |
| **Coder** | Implements one phase at a time against the approved plan | Step 3 |
| **Research** | Answers the coder's questions with real `file:line` evidence — code behaviour, product domain, external APIs | on demand, throughout Step 3 |
| **Reviewer** | Reads the **diff** in a clean context, tries to **refute** it | Step 3.5 |
| **UX** | **Designs** the interface: layout, components, display copy, a mockup you can actually look at | Step 2 — alongside scout, only for phases with UI |
| **Checker** | Runs it for real: lint, tests, browser, logs | Step 4 |

**Why research is a separate session instead of letting the coder look things up:** a coder mid-flow loses momentum when it stops to research, so it tends to guess and move on. A session whose *entire job* is looking things up has no such pressure. This is also the single largest friction category in the audit — 127 times the user had to ask *"dẫn chứng đâu"* (where is your evidence), more than every other category.

**UX designs FIRST, it does not verify afterwards.** It decides what the interface should look like and hands a mockup to the coder — running in the same phase as scout. Re-checking the UI after the code is written belongs to **checker** (which dispatches `ui-ux-reviewer`); no separate role needed.

With no mockup the coder invents its own and the user has to correct it later — that is exactly where things go wrong.

## Who holds the work at each step

| Step | Holds the work | Who joins in | User |
|---|---|---|---|
| 0 · Orient, pick MODE | Parent | — | — |
| 1 · Intake, verify spec | Scout | — | — |
| 2 · Flow-check + plan + UI design | Scout + **UX** | Parent consolidates | 🚦 **approve plan + mockup** |
| 3 · Code phase N | Coder | **Research** answers on demand; implementers dispatched in parallel | — |
| 3.5 · Read the diff | Reviewer | findings → Coder fixes | — |
| 4 · Run it for real + re-check UI | Checker | red → Coder fixes | — |
| — · Converged | Parent gathers evidence | — | 🚦 **approve code** |
| 5 · Finalize | Parent | — | — |
| 6 · Ship-out | Parent | — | 🚦 **decide deploy/merge** |
| 7 · Deploy + end-of-round review | Parent | 4 review agents in parallel | — |

At any step: a design trade-off, missing information, or hitting the three-round limit → 🚦 **ask the user**, never decide it yourself.

## Life of one phase

```
        ┌── Coder asks ──► Research answers with file:line ──┐
        │   (any time it is unsure — guessing is banned)     │
        └───────────────────────◄───────────────────────────┘
                          │
Coder finishes ──► Reviewer reads the diff (clean context, tries to refute)
                          │
              any must-fix findings left?
                    ├─ yes ──► Coder fixes ──► back around (max 3 rounds)
                    └─ no  ──► Checker runs it for real (lint/test/browser/log)
                                      │
                            machine says green?
                              ├─ no  ──► Coder fixes (counts toward the 3 rounds)
                              └─ yes ──► Parent gathers → 🚦 user approves code
```

## Four rules that keep the loop from breaking

1. **The final judge is a machine, not a model.** "Done" is only valid with deterministic evidence: tests pass, lint clean, screenshot, real logs. "The reviewer says it's fine" does not count.

2. **Kill after 3 rounds.** Coder ↔ reviewer past three rounds without converging → stop and escalate with the exact point of disagreement. That is gate type 3 (user decides), not a failure.

3. **The reviewer is barred from padding.** Only flag things that affect **correctness** or **a requirement stated in the plan**. A reviewer prompted to find problems will always invent something if left unbounded — every finding needs `file:line` plus a concrete failure scenario, otherwise drop it.

4. **Child sessions must DIE after each phase.** Measured 07/08: four child sessions ran **40–45 hours straight**, transcripts up to **14 MB**. Consequences:
   - **Instructions never refresh.** A kickoff is read ONCE at startup. The dispatch rule was added to the template on 06/08 but those sessions started on 05/08 → they never saw it. Result: **zero implementer dispatches** across every session, even though the tool was available and the rule existed.
   - **Longer means slower and more expensive** — every turn carries a 14 MB context.
   - **Longer means further from its instructions** — rules at the top of the kickoff get pushed far back, and the model follows them less.

   So: **finish a phase → exit the session → the parent restarts it for the next phase.** That both loads the latest kickoff and resets the context. The reviewer already needed a clean context per phase; the same now applies to coder and checker.

   `/ship-board` has a **SESSION** column showing age and size, flagged **⚠** past 12 hours or 5 MB — that mark means restart it, do not let it run on.

   **The parent must repeat the rules when handing out work — never assume a session remembers.** For example:

   > `call coder "P5: touches admin + backend. Dispatch admin-frontend-implementer and backend-implementer in parallel, then merge the results yourself. Reminder: declare your pattern reference before writing any new code."`

## The user is involved at exactly 3 points

| Gate | When | What the parent must attach |
|---|---|---|
| **plan** | Scout finished `plan.html`, UX finished the mockup | Phase list, trade-offs, open decisions, **a mockup you can look at** |
| **code** | Reviewer and Checker are both green | The diff, what the reviewer caught and how the coder handled each, screenshots from checker, REAL test output |
| **decision** | Any design trade-off, missing context, or hitting the 3-round limit | The precise question + the options + a recommendation backed by numbers |

Outside these three, **do not interrupt the user**. But never skip ahead either: commit/push still needs the user's agreement **in that same turn** — a rule now, with no hook enforcing it (the user removed that hook on 07/08 because it over-blocked). And **never write to memory on your own** — the `memory-consent` hook does still block that.

## What the parent runs

1. `git worktree add ~/cmux/worktrees/<repo>/<slug> -b <type>/<slug>` (see the `cmux-worktree-orchestration` skill). Task needs the local dev stack? Use `feature-open --main` instead and work directly in the main checkout.
2. **`.claude/scripts/bootstrap-worktree.sh <path>`** — mandatory. A bare worktree has NO ship and NO hooks; skipping this releases an agent with no rules at all. The script self-verifies; if it fails, do not open a session.
3. Create `.claude/ship/<slug>/progress.md` with the `<!-- state ... -->` block at the top (see `templates/progress-header.md`).
4. Open child sessions per role, each with its matching kickoff from `templates/role-*.md`. Start them with `claude --dangerously-skip-permissions` — an unattended session freezes on any command containing `$(...)` or a pipe without that flag. Hooks **still** block in bypass mode (verified 2026-08-05), so the guardrails hold; but that is precisely why the bootstrap step cannot be skipped — a worktree missing hooks *plus* bypass mode is a genuinely unconstrained agent. **Do the research in the parent session first, then write the kickoff** — a child session has no memory of this conversation; anything not written down is lost.
5. After each turn: update the state block (`role`, `round`, `awaiting`, `gate`) — this is what `ship-board.sh` reads to render the multi-feature table.
6. Escalate only at the three gates, always with evidence.

`.claude/scripts/ship-board.sh` — the table of every running feature, with whatever is waiting on the user sorted to the top.
