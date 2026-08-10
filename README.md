# claude-harness

A Claude Code harness for running **several specialised sessions in parallel on one feature**:
scout, coder, research, reviewer, ux, checker — each in its own terminal tab, all on one git
worktree, escalating to you at only three gates.

📖 **[harness-book.html](harness-book.html)** is the handbook: install, the workflow, and the
traps that cost real time. Open it in a browser; it is the real documentation.

## Install

```bash
git clone https://github.com/MeanHoang/claude-harness ~/claude-harness
cd ~/claude-harness

./install.sh /path/to/project           # copy into the project (default)
./install.sh /path/to/project --link    # symlink instead, one shared source
```

Default is **copy**: this is a package you paste into a project, and each project is then free to
diverge. Nothing at the destination is destroyed — a pre-existing real file is renamed to
`*.bak.<timestamp>` first. `settings.json` and `settings.local.json` are never written, because
they carry per-project permissions and hook wiring; wire the hooks by hand after installing.

## What you get

13 skills, 7 hooks, 5 scripts. A development workflow, not a dev-stack setup: nothing here
knows how your app boots, and nothing is tied to a particular product.

**Running work in parallel**
`feature-team` (one feature, many specialised sessions, 3 user gates) · `feature-open` (one command:
worktree + harness + progress.md + cmux workspace + 6 role tabs) · `ship-board` (table of every
running feature, whatever waits on you sorted to the top) · `task-catchup` (what landed on your
tasks while you were heads-down)

**Getting a task done**
`analyze-task` (verify every claim of a spec against real code before planning) · `ship`
(end-to-end pipeline: intake → plan → implement per phase → test → ship, user at the gates only) ·
`branch-focus` (orient fast on a branch you left days ago) · `merge-branch` (merge plus impact
audit, with the per-hunk technique that avoids the `--theirs` data-loss trap)

**Bugs**
`bug-check` (diagnose and STOP: three legs, one of four verdicts, never fix)

**Testing**
`test-environments` (which store belongs to which app, how to set up data, how to log in as a
customer) · `surface-audit` (a coverage-audit method so a feature does not ship to four surfaces
when it has five)

**Housekeeping**
`update-handle` (mirror what you just did onto a markdown kanban card) · `skill-creator` (scaffold
a new skill)

**Hooks** — `readonly-intent-guard` (deny writes when the session was told to only read) ·
`branch-guard` · `memory-consent` · `commit-consent` (ships disabled) · `auto-lint` (lints only the
lines actually changed) · `block-dangerous-bash` · `recursion-guard`

**Scripts** — `feature-open.sh` · `bootstrap-worktree.sh` (equip a fresh worktree so agents run
under the guards) · `ship-board.sh` · `shot.sh` (screenshots that do not flood the context) ·
`env_loader.py`

## Fill in your own values

Project-specific values were stripped before publishing and replaced with `{{VARS}}`: store
package paths, cloud project ids, git remote, store domains, test identities. 14 in all.

```bash
cp harness.config.example harness.config     # fill it in; it is gitignored
./fill-vars.sh /path/to/project harness.config
```

`fill-vars.sh` is idempotent, and any `{{VAR}}` with no matching key is left alone and reported —
nothing is silently replaced with an empty string.

Two skills ship deliberately hollow:

- **`surface-audit`** keeps the audit *method* but the surface inventory is an empty template. That
  map is a description of a specific product; it is knowledge, not tooling.
- **`test-environments`** keeps the procedure, with credentials as variables. The mail-reading step
  still needs `TEST_MAIL_USER` / `TEST_MAIL_APP_PASSWORD` as real environment variables at run time.
  That app password can read a real mailbox — scope it to one-time-code lookups only.

## Why it exists

The harness grew inside one product repo, and most of the valuable parts were **deliberately kept
out of git** (`.git/info/exclude` plus a couple of `skip-worktree` entries). That combination is
silently lossy:

- `.git/info/exclude` is itself a local file. It is never committed and never pushed, so a fresh
  clone on another machine has none of it, with no warning.
- `skip-worktree` tells git to pretend a tracked file never changes. A stray `git checkout` or
  `git stash` discards the local edits without a word, and they can never be pushed.

An audit on 2026-08-08 found **41 files / 428 KB living in no git repository at all**. This repo is
the fix, and the split into a portable layer is what lets the machinery travel without dragging
along one product's internal knowledge.

## Scope

Only the **generic** machinery is published here. Product-specific skills (business surfaces, test
environments and credentials, internal task boards, deploy pipelines) stay private in their own
repo — they are company knowledge, not tooling.

## Requirements

`git` (worktrees), `python3` (ship-board), and [cmux](https://cmux.io) for workspaces and tabs.
Without cmux the worktrees still work; you just open the sessions by hand.
