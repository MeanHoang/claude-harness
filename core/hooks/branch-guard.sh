#!/usr/bin/env bash
# PreToolUse(Bash): guard the two git mistakes that cost real work.
#
# 1. `git stash -u` / `--include-untracked` — swallows untracked files AND an
#    in-progress merge into stash^3, where `git diff` does not show them.
#    Ratchet trace: feedback_never_stash_include_untracked.
#
# 2. commit/push while checked out on ANOTHER task's branch. The working dir gets
#    switched mid-session, and a fix once landed on the wrong MR.
#    Ratchet trace: feedback_verify_git_branch_before_commit.
#    Detection: the ship slug most recently mentioned in this session's transcript
#    declares its branch in .claude/ship/<slug>/progress.md ("Branch: `name`").
#    No slug mentioned → no claim to check against → allow (part 1 still applies).

set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# `git` counts as a COMMAND only at the start of the string or straight after ; & | ( —
# not after arbitrary whitespace. Otherwise a command that merely *mentions* "git commit" in
# text (writing docs, editing this very hook) gets blocked too. That trap fired for real on
# 2026-08-05.
G='(^|[;&|(])[[:space:]]*git[[:space:]]+'

# --- 1. stash that swallows untracked files ---
if printf '%s' "$cmd" | grep -qE "${G}stash" \
   && printf '%s' "$cmd" | grep -qE '(--include-untracked|--all([[:space:]]|$)|(^|[[:space:]])-[a-zA-Z]*[ua][a-zA-Z]*([[:space:]]|$))'; then
  deny "STOP: git stash -u/--include-untracked swallows untracked files AND an in-progress merge into stash^3, where git diff does NOT show them. Use git stash push -- <specific files>, or a temporary commit on the branch."
fi

# --- 2. blanket staging ---
# the ship skill already forbids this in prose; a worktree makes it dangerous enough to gate.
# The harness symlinks .claude/skills/* into each worktree, so `git add -A` there would
# commit absolute-path symlinks into the repo.
if printf '%s' "$cmd" | grep -qE "${G}add[[:space:]]+(-A([[:space:]]|$)|--all([[:space:]]|$)|\.([[:space:]]|$))"; then
  deny "STOP: do not use git add -A / git add . — stage explicit paths. (In a worktree, a bulk add swallows the harness symlinks into the repo.)"
fi

# --- 3. commit/push on another task's branch ---
printf '%s' "$cmd" | grep -qE "${G}(commit|push)([[:space:]]|$)" || exit 0

project=${CLAUDE_PROJECT_DIR:-$(pwd)}
current=$(git -C "$project" branch --show-current 2>/dev/null)
[ -n "$current" ] || exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

slug=$(grep -oE '\.claude/ship/[a-z0-9._-]+' "$transcript" 2>/dev/null | tail -1 | awk -F/ '{print $3}')
[ -n "$slug" ] || exit 0

progress="$project/.claude/ship/$slug/progress.md"
[ -f "$progress" ] || exit 0

declared=$(grep -oE 'Branch: *`[^`]+`' "$progress" 2>/dev/null | head -1 | sed -E 's/.*`(.*)`/\1/')
[ -n "$declared" ] || exit 0
[ "$declared" = "$current" ] && exit 0

deny "STOP: the current branch is '$current' but task '$slug' declares '$declared' in progress.md. Another session may have switched this working directory. Check with git branch --show-current and check out the right branch before you commit or push."
