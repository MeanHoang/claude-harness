---
name: update-handle
description: "Sync the current work in this code repo back to the update-handle board (../update-handle), then commit & push it. Use when the user says '/update-handle', 'update doc', 'cập nhật board', 'sync handle', 'làm đến đâu update đến đó', or after finishing a phase/commit and wanting the kanban card to reflect progress. Reverse direction of the old hub-orchestrates flow: code lives here, the card is updated FROM here."
---

# update-handle — push progress from the code → update-handle board

update-handle (`../update-handle`, GitHub `MeanHoang/update-handle`) is a personal kanban where **markdown is the source of truth**. Each task = `tasks/<slug>/` with `_meta.md` + lens files (`ba/plan/dev/review` for feature, `fix` for bug). A read-only Next.js viewer redeploys on push.

This skill runs **from inside a code repo** (any working copy, including numbered clones like `repo-2`). You did the real work here; now reflect it onto the matching card and push so the board (and Vercel viewer) update.

## Hard rules (inherited from update-handle — do NOT break)

1. **Never auto-bump `status`.** Only step 1 (`gather`/`localize`) may auto-advance — and that happens in the hub, not here. Update progress + `branch`/`mr`/`updated` freely; bump `status` (or `env`) **only when the user explicitly says OK in this conversation.** If the work looks done but they haven't said move it, leave `status` as-is and say so.
2. **Notes here are lighter than the repo's output.** Summarize: what got done, why this approach, open bugs + which env. **Link the branch/MR — never hand-paste code.** Git is the source of truth.
3. **Surgical card edits.** Touch the card you're updating. Don't reformat other cards or restructure the board.
4. **The commit+push targets `../update-handle` only** — never the code repo. (Auto-commit here is intended; it does not touch the code repo's git.)

## Workflow

### 1. Read context from this repo
- `repo` = current folder name (`basename $(pwd)`).
- `branch` = `git branch --show-current`.
- What changed since last sync: `git log --oneline -15`, and if useful `git log --stat -3`. Use the user's own description of what they just did as the primary source; git is the backstop.
- If an MR/PR URL exists, capture it (ask the user if you can't find it — never invent one).

### 2. Locate the matching card in ../update-handle
Read `../update-handle/tasks/*/`_meta.md` frontmatter (`title, type, status, env, repo, branch, mr, updated`). Match priority:
1. Card whose `branch:` == current branch → use it.
2. Else cards where `repo:` == current repo → if exactly one obvious match by title/slug, confirm with the user; if several, list them and ask which.
3. Else no card → tell the user. Offer to create one from the right template (`tasks/_template-feature/` or `_template-bug/`) **only if they confirm** (slug = kebab-case of the title). Don't silently create.

Never guess across the wrong repo — a card's `repo:` must match where the code actually is.

### 3. Update the card (lighter-than-repo summary)
- **`_meta.md`**: set `branch`, `mr` (if one exists), `env` (only if the user says it moved), `updated: <today YYYY-MM-DD>`. Leave `status` unless explicitly told to move it (rule 1).
- **Progress lens** — append/refresh the relevant file, matching the template's existing structure & tone:
  - feature → `dev.md` (tick done parts, note the phase, open bug + env). Plan/review belong in `plan.md`/`review.md` if that's what changed.
  - bug → `fix.md` (Nguyên nhân / Giải pháp / Tiến độ-retest, which env is failing).
- Keep your project's own expensive-mistake reminders in mind when summarizing (whatever CLAUDE.md lists — tenant scoping, webhook deadlines, index coverage, translations, bulk limits) — flag any that apply as an open item.

### 4. Commit & push to update-handle
Run git **inside `../update-handle`** (use `git -C ../update-handle ...` so the code repo's shell cwd is untouched):

```bash
git -C ../update-handle add tasks/<slug>
git -C ../update-handle commit -m "<type>(<slug>): <one-line of what changed> [<repo>@<branch>]"
git -C ../update-handle push
```

- Commit message: short, imperative, says what progress was recorded. Example: `feature(some-feature): record P1 backend done, set branch [project@feature/...]`.
- Push to `origin` (current branch is `master`). If push is rejected (remote ahead), `git -C ../update-handle pull --rebase` then push; surface conflicts instead of force-pushing.
- Report back: which card, what fields changed, status left at `<x>` (and why, if it looked done), and the pushed commit hash. Note that Vercel will redeploy the viewer.

## Quick reference
- Board overview: `/board` inside update-handle (or read `tasks/*/_meta.md`).
- Columns — feature: `gather→verify→plan→coding→staging→test-staging→review→production→done` · bug: `localize→reproduce→identify→fix→production`.
- `env` (`local|staging|production`) is tracked separately from `status`.
