---
name: merge-branch
description: Safely merge into a branch and assess impact. Use when the user says "merge master vào branch", "merge master into branch", "resolve conflict", "xử lý conflict merge", "merge branch vào branch merge", "gộp các task để test", or any git merge that needs conflict resolution + impact analysis. Two contexts — (1) master → feature branch (read the feature doc, audit every master commit for hidden bugs, resolve conflicts, update the doc with impacts), (2) feature branch → integration/merge branch (find which incoming branch caused each conflict + its impact, fix). Encodes the per-hunk union technique that avoids the `git checkout --theirs` whole-file data-loss trap.
---

# Merge Branch — Conflict Resolution & Impact Assessment

## ⚠️ Prime directive — the user does NOT re-check your work

The user cannot and will not re-verify the merge afterward. **You are the only safety net.** A wrong resolution ships silently.

- **Correctness over cost.** Spend whatever tokens/time/tool-calls it takes. Read every relevant file in full, audit every commit, run every verification. Never trade thoroughness for brevity here.
- **Prove, don't assume.** Every claim ("no impact", "lossless", "both families present") must be backed by a command output you actually ran in this session — not reasoning, not "should be fine". If you didn't run the check, you don't know.
- **A clean build is not verification.** JSON parsing, lint, or a successful merge commit only prove syntax. They say nothing about lost keys, dropped logic, or a master change that silently breaks the feature. Verify behavior/content, not just that it parses.
- **When unsure, escalate effort, don't guess.** Re-read the source, diff base↔ours↔theirs, `git log -L` the exact function, spawn a subagent to double-check. Surface any residual doubt explicitly to the user instead of resolving it silently.
- **Self-review before declaring done.** Re-open every file you resolved, re-run the §A5 verification block, and confirm 0 unmerged + valid + both sides present. Only then report.

If any verification cannot be run (tool missing, build won't start), say so plainly — never paper over a gap with an assumption.

---

Two contexts. Pick by what's being merged.

| Context | Into | Goal |
|---|---|---|
| **1. master → feature branch** | a single-feature branch (e.g. `feat/...`) | keep feature intact; catch master changes that break it even without a conflict |
| **2. feature branch → integration branch** | a "merge branch" that collects many tasks for QA | find which incoming branch caused each conflict + its blast radius |

---

## 🔴 The one rule that prevents data loss

**NEVER resolve a conflicted file with `git checkout --theirs/--ours -- <file>`.**
That replaces the **entire file** with one side's blob. If the *other* side added unique content **outside** the conflict block (very common in append-style files like translations), it is silently deleted.

Real failure this skill exists to prevent: feature branch added 3 recurring widget keys near the top of `en.json`; master appended WidgetV4 keys at the bottom → conflict only at the bottom. `--theirs` wiped the 3 recurring keys at the top. JSON stayed valid, so the bug was invisible until grep.

**Always resolve per-hunk** (union): keep the whole file, replace only each conflict block's content with the side you want. Recipe in §A4.

---

## Context 1 — master → feature branch

Order matters: **understand the feature first**, then audit commits, then resolve, then commit, then write impacts back.

### Step 1 — Read the feature doc, master the flow & edge cases

Most features have a design doc. Find it:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
# branch name → likely doc keyword (e.g. feat/milestone-recurring-mode → "recurring|milestone")
find docs -iname '*.md' | grep -iE 'recurring|milestone|<feature-keyword>'
git log --oneline master..HEAD | head -40   # commit subjects name the feature
```

Read it fully. Note especially: **state model, writer isolation, edge cases, "Out of Scope", and any existing "Post-Merge Follow-ups" section** — these tell you what master could break. Per project memory `feedback_notion_ai_gen_verify`: trust the goal, verify field/logic claims against code.

### Step 2 — Audit EVERY master commit for impact (incl. hidden bugs, not just conflicts)

> Auto-merged-clean ≠ safe. A master commit can change a shared function's behavior with zero conflict and silently break the feature.

```bash
INCOMING=$(git rev-parse MERGE_HEAD 2>/dev/null || echo origin/master)
BASE=$(git merge-base HEAD $INCOMING)

# List the files THIS FEATURE owns (from the doc's "Files Changed" table + git diff)
git diff --name-only $BASE...HEAD | grep -iE '<feature paths>'

# For each owned file, did incoming master touch it since the branch's last merge?
for f in <owned files...>; do
  n=$(git log --oneline $BASE..$INCOMING -- "$f" | wc -l | tr -d ' ')
  [ "$n" != 0 ] && echo ">>> $f : $n incoming commits" && git log --oneline $BASE..$INCOMING -- "$f"
done
```

For every file master **did** touch, verify the feature's logic survived semantically:

```bash
# Did master change the SPECIFIC function the feature relies on? (empty = safe)
git log -L ':<functionName>:<path>' $BASE..$INCOMING -s --oneline

# Then read the function in the working tree to confirm the feature's branch is intact
grep -n '<feature marker e.g. recurringMilestone|milestoneMode>' <path>
```

Classify each touched-but-clean file:
- **Untouched by master** → safe, skip.
- **Touched, different function** → confirm with `-L` that the feature's function wasn't changed.
- **Touched, same function/region** → read both versions; this is where hidden bugs hide. Flag it.

Also scan master commit subjects for features that share the feature's **runtime path / state fields / event handlers** even if they don't touch the same file (e.g. a new earning condition that fires on the same order event). These are the non-obvious ones.

### Step 2.5 — Trace EVERY collision to its source branch + Notion task (the "who/what/why" of each P-item)

A conflict or hidden-bug overlap is never anonymous — some other branch caused it. Before you write a P0/P1/P2, **identify the incoming work behind it** so the follow-up is actionable, not just "master changed something". Do this for each genuine collision (real-code conflicts + touched-same-region hidden bugs), not for trivial additive/translation unions.

```bash
# 1. Which branch/MR brought the incoming change to this file? (the other party)
git log $BASE..$INCOMING --merges --oneline --ancestry-path <commit-that-touched-file>..$INCOMING | tail -3
git log $BASE..$INCOMING --oneline --no-merges -- <file>     # the actual work commits + author
git show -s --format='%h %an %s' <commit>                    # author tells you the dev to ask

# 2. Read the ACTUAL diff of the colliding work, not just subjects — is it additive, guarded,
#    or does it really overlap your feature's path?
git diff $BASE..$INCOMING -- <file> | head -120
```

Then map the branch → **Notion task** and summarise. Use the `notion-tasks` skill (or `my-tasks`) — search by the branch keyword / commit author / feature name (e.g. branch `improve/referral-notification` → search Notion "referral notification"). For each collision, surface to the user **in chat** (this is the part that makes the P-item useful):

```
<branch> (author) — Notion: <link or "not found, searched X">
  Task là gì:   <1-line what the incoming task does>
  Phân tích:    <additive / event-guarded / genuinely overlaps your feature's function>
  Ảnh hưởng:    <concrete: breaks build / changes shared field / parallel & independent / nil>
```

Keep this richer task-level analysis **in the chat report**. The md doc (Step 5) gets only the terse P0/P1/P2 lines (+ optionally the Notion link) — do NOT paste the full per-branch analysis into the md (per project memory `feedback_docs_out_of_commits`; the user reads the deep analysis in chat, the doc stays a clean checklist).

> Verify before you trust a label: "additive/guarded" must be backed by the diff you actually read (e.g. confirm the incoming code is gated by `if (event === OTHER_EVENT)` and your feature has its own dedicated branch/case). A subject line saying "referral" doesn't prove it can't touch your gift-card path — read both code paths.

### Step 3 — Analyze the actual conflicts (source + severity)

```bash
git diff --name-only --diff-filter=U                       # what's conflicted
git diff --name-only --diff-filter=U | sed 's|/[^/]*$||' | sort | uniq -c   # by dir
# Non-data conflicts (the ones that need real thought):
git diff --name-only --diff-filter=U | grep -vE 'locale/output|storage/translations|\.lock|generated'
```

For each conflict, characterize the **shape** before resolving:
- **Additive / append** (both sides add keys) → union (§A4).
- **Same key, different value** (master reworded) → usually take master's newer value; confirm no side-only keys are lost (§A3).
- **Generated file** (`locale/output/*`, lockfiles) → resolve to unblock, then **regenerate** from source (`yarn update-label` for admin labels; input lives in `locale/input/*` — check it merged clean). See project memory `feedback_translation_workflow`.
- **Real code conflict** → understand both intents, resolve by meaning, never by picking a side blindly.

### Step 4 — Resolve, verify, commit

Resolve every conflict (§A4 union for additive, by-meaning for code), then **verify before committing**:

```bash
test -z "$(git diff --name-only --diff-filter=U)" && echo "0 unmerged ✅"
# JSON files must parse:
for f in <resolved json>; do node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))" || echo "INVALID $f"; done
# Both content families survived (the --theirs trap check):
grep -c '<feature-only key>' <file>    # must be > 0
grep -c '<master-only key>'  <file>    # must be > 0
```

Commit only when the user says so (project memory `feedback_git_workflow` — never auto-commit). Merge commits often want `[skip-ci]` when only translations changed — **ask / honor the user's call**. End the message with the Co-Authored-By trailer.

### Step 5 — Write impacts back into the feature doc

Append a dated **`## Post-Merge Follow-ups — master → branch (YYYY-MM-DD)`** section to the feature's md, with a severity-tagged list (🔴 P0 / 🟠 P1 / 🟡 P2 / 🟢 P3) of anything Step 2 surfaced:

```markdown
## Post-Merge Follow-ups — master → <branch> (<date>)
Discovered while merging master (merge commit `<sha>`). Conflicts resolved; items below are NEW work the merge surfaced.

### 🔴 P0 — <title>
- What master changed: <commit/file>
- Impact on this feature: <concrete failure mode>
- TODO: <fix>
```

If Step 2 found **nothing**, say so explicitly in the doc (and to the user) — "no incoming master commit affects the feature; X and Y overlapped files but auto-merged clean and the feature's functions are verified intact." A clean bill of health is a result worth recording.

> Per project memory `feedback_docs_out_of_commits`: keep these doc edits OUT of the code commit. Update the doc as a separate change for the user to review.

---

## Context 2 — feature branch → integration / "merge" branch

An integration branch gathers many task branches so QA can test them together. Here you don't have one feature to protect — you have N, and conflicts mean **two tasks touched the same code**.

### Workflow

```bash
git merge <task-branch>          # or it's already in progress
git diff --name-only --diff-filter=U
```

For each conflicted file, the questions are **which task** and **do they actually clash**:

```bash
# Which already-merged branch last touched this region? (the other party to the clash)
git log --oneline -5 <file>
git blame -L <start>,<end> <file>         # who owns each conflicting line

# What is the incoming task trying to do here?
git log --oneline <integration>..<task-branch> -- <file>
```

Classify the clash:
- **Independent edits, same hunk** (both valid, different lines) → union, keep both.
- **Same logic, two implementations** → the tasks genuinely overlap. **Don't silently pick one** — report to the user which two tasks collide and the behavioral difference; they decide.
- **One supersedes the other** → keep the newer intent, note the superseded task.

### Report format (Context 2)

For each conflict, tell the user:
```
<file>:<lines> — task A (<branch>) vs task B (<branch>)
  A wants: ...   B wants: ...
  Resolution: <union / kept A / kept B>  — reason: ...
  Impact: <does the test scenario for A or B change?>
```

Then resolve and commit (with the user's go-ahead). Integration branches are throwaway/QA — `[skip-ci]` is common, but confirm.

---

## Appendix A — Conflict recipes

### A1. See merge state
```bash
test -f .git/MERGE_HEAD && echo "merge in progress: $(git log -1 --oneline $(cat .git/MERGE_HEAD))"
git diff --name-only --diff-filter=U
```

### A2. Inspect one conflict block
```bash
grep -n '^<<<<<<<\|^=======$\|^>>>>>>>' <file>                 # block boundaries
awk '/^<<<<<<</{p=1} /^>>>>>>>/{p=0} p' <file>                 # print the blocks
git show :1:<file>  # base   :2:<file> ours   :3:<file> theirs
```

### A3. Will taking one side lose keys? (run BEFORE deciding --theirs is "safe")
```bash
ours=$(awk '/^<<<<<<</{s=1;next}/^=======/{s=0}/^>>>>>>>/{next}s' <file> | grep -oE '"[^"]+":' | sort -u)
theirs=$(awk '/^=======/{s=1;next}/^>>>>>>>/{s=0}s' <file> | grep -oE '"[^"]+":' | sort -u)
comm -23 <(echo "$ours") <(echo "$theirs")   # keys in OURS not in THEIRS = lost if --theirs
```
Remember this only inspects the **conflict block**. Content **outside** the block is what `--theirs` whole-file deletes — that's why §A4, not `git checkout`, is the resolution.

### A4. Per-hunk UNION (keep both sides' additions) — the safe default for additive files
```bash
# Keeps every non-conflict line + the THEIRS side of each block (drops ours-portion + markers).
# To prefer OURS inside blocks instead, swap which side the awk keeps.
awk '
  /^<<<<<<< /{drop=1; next}
  /^=======$/{drop=0; next}
  /^>>>>>>> /{next}
  !drop{print}
' <file> > <file>.tmp && mv <file>.tmp <file>
```
For a true union that keeps **both** sides inside the block (no key dropped), keep both portions — only strip the three marker lines:
```bash
grep -v '^<<<<<<< \|^=======$\|^>>>>>>> ' <file> > <file>.tmp && mv <file>.tmp <file>
# then dedupe / fix the trailing-comma between the two glued blocks if it's JSON
```

### A5. Validate + finish
```bash
for f in <files>; do node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))" || echo "INVALID $f"; done
git add <resolved files>
test -z "$(git diff --name-only --diff-filter=U)" && echo "ready to commit"
```

### A6. Regenerate generated locale output (don't hand-merge)
`{{PKG_ADMIN}}/src/locale/output/*.json` is generated from `locale/input/*`. If input merged clean, resolve output just to unblock, then:
```bash
yarn update-label   # regenerates output authoritatively from merged input
```

---

## Checklist

**Context 1 (master → feature):**
- [ ] Read the feature md — flow + edge cases + existing follow-ups
- [ ] Audited every master commit touching owned files; `-L` on the feature's functions
- [ ] Scanned master subjects for shared runtime-path/state-field features (hidden bugs)
- [ ] Traced each genuine collision → source branch + Notion task (read the diff); reported who/what/analysis/impact in chat (rich analysis stays in chat, not md)
- [ ] Characterized each conflict's shape & source before resolving
- [ ] Resolved per-hunk (NO whole-file `--theirs`); 0 unmerged; JSON valid; both families present
- [ ] Committed only on user's say-so (honor `[skip-ci]`)
- [ ] Wrote dated Post-Merge Follow-ups into the md (or recorded "no impact"), kept out of the code commit

**Context 2 (branch → integration):**
- [ ] For each conflict: identified the two colliding tasks (`blame` + `log`)
- [ ] Classified independent-union vs genuine-overlap vs supersede
- [ ] Reported genuine overlaps to the user instead of silently picking
- [ ] Resolved, verified, committed on user's say-so
