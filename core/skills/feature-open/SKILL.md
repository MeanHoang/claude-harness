---
name: feature-open
description: Open a work item to run in parallel — create the git worktree, equip it with the harness, create its own cmux workspace with 6 role-named tabs (scout/coder/research/reviewer/ux/checker), and write a kickoff for every role. Use when the user says "/feature-open <slug>", "mở feature mới", "tạo workspace cho task này", "chạy task này song song", "mở worktree cho <task>", or wants to start another work item alongside the current one.
---

# Open a work item to run in parallel

```bash
.claude/scripts/feature-open.sh [--main] <slug> [notion-url] [feature|bugfix|chore|improve]
```

One command does six things: worktree → harness → `progress.md` → cmux workspace → six role tabs →
a kickoff per role.

**`--main` — work directly in the main checkout, no worktree.** Use it when the task needs the
**local dev stack**: the dev stack runs from the main checkout, and a separate worktree would have
to rebuild `node_modules` plus its own tunnel. It is also the way out when the branch is already
held by the main checkout — git will not let two worktrees hold the same branch. This mode skips
bootstrap, since the main checkout *is* the source of the harness.

## Before running it

Ask the user for two things if missing: the **slug** (kebab-case, used for both branch name and
workspace name) and the **Notion link**. Infer the branch type from the nature of the work —
`bugfix` for defects, `feature` otherwise.

The script aborts if the harness bootstrap fails. That is deliberate: a worktree without the
harness has no `ship`, no gates, and auto-lint will reformat whole files. **If you see that
error, do not open a session — fix the harness first.**

## The one manual step that remains

The script writes a kickoff for every role, but leaves scout's **research section empty**. A child
session is born with zero memory: anything not written into that file is lost for good.

So before starting scout, do the research **in the current session** and fill it in:
- The `file:line` findings: where the component lives, what the field is called, whether precedent exists
- Which conventions apply to this task (point at specific `.claude/skills/*`)
- Open questions scout must put to the user directly rather than guess at

Then start scout:

```bash
cmux list-pane-surfaces --workspace <ws>          # get the scout tab id
cmux send --workspace <ws> --surface <id> $'claude --dangerously-skip-permissions "$(cat <kickoff>)"\n'
```

**Why child sessions run `--dangerously-skip-permissions`:** they run unattended, and any command
containing `$(...)` or a pipe cannot be statically analysed by Claude Code, so it always prompts —
the session would sit frozen waiting for a Yes.

**Safe because hooks are not bypassed.** Verified experimentally 2026-08-05: running
`claude --dangerously-skip-permissions -p` with a read-only prompt still had `readonly-intent-guard`
deny the Write, and no file was created. The flag drops the **permission prompt**, not the
**guardrails** — every hook still constrains the child session. Which is precisely why
`bootstrap-worktree.sh` is mandatory: a worktree missing hooks *plus* bypass mode is a genuinely
unconstrained agent.

`cmux send` **does not press Enter for you** — without the trailing `\n` the command just sits in
the terminal, typed but unsubmitted.

The first session in a fresh worktree may hit an interactive "New MCP server found" prompt that
swallows the kickoff. If so: `cmux send-key --workspace <ws> --surface <id> escape`.

## What you end up with

| Where | Who |
|---|---|
| Workspace `{{PROJECT_ROOT}}` | **Parent** — orchestrates, holds state, collects reports. The parent does not enter a worktree. |
| Workspace `<slug>`, root tab | A bare shell for running git/tests by hand |
| Tab `scout` | Runs first: reads Notion, verifies against code, writes the plan |
| Tabs `coder` / `research` / `reviewer` / `ux` / `checker` | Ready but idle — started when their turn comes, kickoffs in `.claude/ship/<slug>/kickoff-*.md` |

The phase lifecycle, the four loop rules, and the three user gates live in the `feature-team` skill.

## Known limits

- The cmux CLI **cannot create groups** (nested folders in the sidebar) — each work item is a flat
  workspace, identified by its slug name.
- **Ids are not stable** — cmux renumbers workspaces and surfaces after a close/reopen. Always look
  them up by name; never hardcode an id, or a message will land in a different feature.
- A workspace's root tab always carries the workspace name and cannot be renamed separately, which
  is why it is left as a shell rather than assigned a role.
- Worktrees live at `~/cmux/worktrees/<repo>/<slug>`, **outside the repo tree**. Never create them
  under `.claude/worktrees/`: the Shopify CLI scans the whole tree, finds duplicated
  `shopify.web.toml` files, and refuses to start `yarn dev`.
