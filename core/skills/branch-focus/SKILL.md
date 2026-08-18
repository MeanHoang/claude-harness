---
name: branch-focus
description: Orient on the current git branch FAST — answer "what is this branch / what task / how far along / what's left" without the user hunting for the design doc. Use at the START of a session after switching branches, or when the user says "đang làm gì", "branch này làm gì", "làm đến đâu rồi", "context branch", "where am I", "what am I working on", "orient me", "focus", "/branch-focus". Auto-maps branch → feature doc, reads its Status/Pending sections, summarizes branch commits + working-tree state + any merge-in-progress, and prints a one-screen orientation card. Read-only; never edits or commits.

allowed-tools: Bash, Read, Glob, Grep
---

# Branch Focus — Fast Context Primer

Goal: in one pass, tell the user (and prime yourself) **what this branch is, what the task is, how far it's gotten, and what's left** — so the next question lands on solid ground. **Read-only. Never edit, stage, or commit here.**

Dev switches branches constantly; finding the right `docs/**.md` by hand each time is the tax this skill removes.

---

## Arguments

Normally none — it reads the branch you are standing on.
`--note "<free text>"` — optional steer, e.g. `--note "chỉ quan tâm phần storefront"`.

A note here changes **what the card emphasises**, not what it is allowed to do: this skill stays read-only, still prints one card, still makes no edits. If the note asks for something outside that (fix it, continue the merge), say so and stop — that belongs to another skill.

## Run this — gather everything in one batch

These are independent; run them together.

```bash
# 1. Identity
git rev-parse --abbrev-ref HEAD
git log -1 --format='%h %s (%cr)'

# 2. In-progress states the user may have forgotten
test -f .git/MERGE_HEAD     && echo "⚠️ MERGE in progress ← $(git log -1 --oneline $(cat .git/MERGE_HEAD))"
test -d .git/rebase-merge -o -d .git/rebase-apply && echo "⚠️ REBASE in progress"
git diff --name-only --diff-filter=U | head        # conflicts if any

# 3. What this branch did vs master (the task's commits)
git log --oneline --no-merges master..HEAD | head -30
git log --oneline --no-merges master..HEAD | wc -l

# 4. Working-tree state = where they physically stopped
git status --short | head -40

# 5. Files the branch changed (the task's surface area)
git diff --name-only master...HEAD | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head
```

## Map branch → feature doc

Derive keywords from the branch name (drop the `feat/`,`feature/`,`fix/`,`merge/`,`chore/` prefix; split the rest on `-`), then search the doc trees:

```bash
BR=$(git rev-parse --abbrev-ref HEAD)
KW=$(echo "$BR" | sed -E 's#^[^/]+/##; s/-v?[0-9]+$//' | tr '-' '|')   # e.g. milestone-recurring-mode → milestone|recurring|mode
find docs -iname '*.md' 2>/dev/null | grep -iE "$KW" | head
# Doc homes (adjust to your repo): docs/features/, docs/plans/, docs/design/features/, docs/hotfix/, docs/superpowers/specs/
```

- **Exactly one match** → that's the doc. Read it.
- **Several matches** → list them, read the best-named one first, mention the others.
- **No match** → say so. Fall back to the branch's commit subjects + changed-file dirs (step 3+5) to infer the task. Offer to skim the top changed files.

## Read the doc's high-signal sections only (don't dump the whole file)

A feature doc front-loads what you need. Pull these:

- **`**Status**:`** line near the top — the single best progress signal.
- **`## Pending Work` / `## Post-Merge Follow-ups`** — what's left + known risks (P0/P1 tags).
- **`## Out of Scope`** — guards you from "fixing" things that are deliberately deferred.
- **`*Last updated:`** footer — how stale the doc is.

```bash
DOC=<path>
grep -nE '^\*\*(Status|Notion|Date)\*\*|^## (Overview|Pending|Post-Merge|Out of Scope)|^\*Last updated' "$DOC"
```
Then `Read` just those line ranges (or the whole file if it's short, < ~150 lines).

> Per project memory `feedback_notion_ai_gen_verify`: the doc's **goal** is trustworthy; specific field/line/flag claims may be stale — verify against code before acting on them. This skill ORIENTS; it doesn't authorize edits off the doc alone.

## Distinguish branch type

- **Feature branch** (`feat/…`, `feature/…`, `fix/…`) → one task. Use its doc as above.
- **Integration / merge branch** (`merge/…`, `integration/…`, `qa/…`) → collects **many** tasks for QA. There's no single doc. Instead enumerate what's been merged in:
  ```bash
  # --first-parent = only the direct merges INTO this branch (skips nested master→feat merges)
  git log --oneline --merges --first-parent master..HEAD | head -20   # each = one task branch folded in
  ```
  Report it as "QA branch bundling: X, Y, Z" and note conflicts/uncommitted state. (For resolving its conflicts, hand off to the `merge-branch` skill.)

---

## Output — one orientation card

Keep it to a screen. Fill only what you actually found (no guessing):

```
🎯 Branch: <name>   (<feature / QA-bundle>)
📄 Doc: <path or "none found — inferred from commits">
📊 Status: <Status line from doc, verbatim>
✅ Done: <1–3 bullets from branch commits>
🔜 Left: <Pending / Post-Merge P0–P3 items, or "doc says complete">
🧭 Working tree: <clean | N uncommitted files | MERGE/REBASE in progress + conflicts>
⏪ Last commit: <hash + subject + relative time>
```

Then **one** focused line: *"Bạn muốn tiếp tục ở đâu — <the most likely next step inferred from Left + working-tree state>?"* — so the user just confirms a direction instead of re-explaining the task.

Do **not** start implementing. This skill ends at the card + the one offer. Wait for the user.

---

## Guardrails

- **Read-only.** No Edit/Write/add/commit/checkout. If the working tree is mid-merge/rebase, report it — don't try to finish it here.
- **Prove, don't invent.** Every line of the card must come from a command you ran or a doc you read. If you couldn't find the doc, say "inferred from commits", not a confident fiction.
- **Be brief.** The point is fast orientation. One card, one offer. Save the deep dive for when the user picks a direction.
- **Stale doc ≠ truth.** If the doc's Status says "done" but `git status` shows uncommitted work or commits exist past the doc's last-updated date, flag the mismatch.

## Checklist
- [ ] Printed branch identity + last commit + in-progress (merge/rebase/conflict) state
- [ ] Mapped branch → doc (or declared "none, inferred from commits")
- [ ] Pulled Status / Pending / Out-of-Scope from the doc (not a full dump)
- [ ] Classified feature vs integration branch and reported accordingly
- [ ] Emitted the one-screen card + a single "continue where?" offer; made no edits
