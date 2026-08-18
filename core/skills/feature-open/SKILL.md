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
.claude/scripts/cmux-say.sh launch <slug> scout
.claude/scripts/cmux-say.sh status <slug>          # confirm: scout should read "running"
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

**Why go through `cmux-say.sh` rather than `cmux send` directly.** Raw `cmux send` does not press
Enter (the trailing `\n` supplies it), does not dismiss the "New MCP server found" prompt that a
fresh worktree hits on its first run and that swallows the kickoff, and — worst — reports success
either way. The script does all three and reads the screen back before returning, so a tab that
never started is loud instead of silently idle.

It also refuses to send a message into a tab that is still a bare shell. Sent raw, the message
would be executed as a shell command.

## What you end up with

| Where | Who |
|---|---|
| Workspace `{{PROJECT_ROOT}}` | **Parent** — orchestrates, holds state, collects reports. The parent does not enter a worktree. |
| Workspace `<slug>`, root tab | A bare shell for running git/tests by hand |
| Tab `scout` | Runs first: reads Notion, verifies against code, writes the plan |
| Tabs `coder` / `research` / `reviewer` / `ux` / `checker` | Ready but idle — started when their turn comes, kickoffs in `.claude/ship/<slug>/kickoff-*.md` |

The phase lifecycle, the four loop rules, and the three user gates live in the `feature-team` skill.

## Deploying or running tooling from inside a worktree

A worktree can now run `yarn`, `eslint`, `shopify app deploy` on its own — bootstrap symlinks
`node_modules` (root + every package + every extension, 19 of them) and `.shopify` back to the
main checkout. Without those, every command failed and the only way out was to go back to the
main checkout — but the branch was held by the worktree, so you had to **delete the worktree just
to deploy by hand**. That loop is what the symlinks cut.

So: **deploy from inside the worktree, do not check the branch out in main.**

```bash
cd ~/cmux/worktrees/<repo>/<slug>
yarn deploy-extensions          # or shopify app deploy --config <cfg>
```

Two things to know about the symlinks:

- **`.shopify` is shared with the main checkout.** It holds `project.json`, the localhost cert and
  the deploy/dev bundle cache. Two worktrees running `shopify app dev` at once will fight over it —
  run the dev stack in one place at a time.
- **`node_modules` is shared too.** If your branch changes `package.json`, the shared tree is wrong
  for it: run `yarn install` inside the worktree, which replaces the symlink with a real directory.
  Bootstrap leaves any real directory alone on later runs.

## Getting a SECOND checkout of a branch a worktree already holds

You want the branch's code in the main checkout too — to run the full dev stack, or to deploy by
hand — while the worktree keeps working on it. Git refuses the obvious form:

```bash
git checkout <branch>                    # fatal: already checked out at <worktree>
git worktree add <path> <branch>         # same refusal
```

Git only forbids two places **holding** the same branch (so two HEADs can never move it at once).
It does not forbid two places **sitting on** the same commit. So detach:

```bash
git checkout --detach <branch>           # main now has that exact code, holds no branch
yarn dev / yarn deploy-extensions        # run whatever you needed
git checkout <your-previous-branch>      # go back when done
```

Verified 2026-08-08: `git worktree add --detach <path> <branch>` succeeds against a branch already
held elsewhere; both land on the same commit and the worktree keeps its branch untouched.

**The one caveat: you are on a detached HEAD.** Commits made there belong to no branch and are
easy to lose. Read, run, deploy — do not commit. If you did commit by accident, `git branch
<name> <sha>` before switching away rescues it.

**Never delete the worktree just to free the branch.** That throws away its harness symlinks, its
`progress.md` state and its cmux tabs, for something `--detach` solves in one command.

The reverse direction, when you want the branch itself in main rather than just its code:

```bash
git -C ~/cmux/worktrees/<repo>/<slug> checkout --detach   # releases the branch, keeps the worktree
git checkout <branch>                                   # now main can take it
```

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
